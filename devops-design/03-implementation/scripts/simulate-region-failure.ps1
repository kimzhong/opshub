# Chaos injection: full region A failure
# PowerShell 5.1 compatible
# Demonstrates: cross-region DR failover
# WARNING: this deletes the biz-prod-regiona kind cluster
# Usage: powershell -ExecutionPolicy Bypass -File simulate-region-failure.ps1
$ErrorActionPreference = 'Stop'

Write-Host '========================================' -ForegroundColor Red
Write-Host ' DR Drill: Region A Complete Failure' -ForegroundColor Red
Write-Host '========================================' -ForegroundColor Red
Write-Host ''
Write-Host '[WARN] This will delete the biz-prod-regiona cluster' -ForegroundColor Red
Write-Host '         to demonstrate failover to region B.' -ForegroundColor Red

Write-Host ''
Write-Host 'Continue? (yes/no): ' -NoNewline
$confirm = Read-Host
if ($confirm -ne 'yes') {
    Write-Host 'Cancelled' -ForegroundColor Yellow
    exit 0
}

# ---- Step 1: validate both regions ----
Write-Host ''
Write-Host '[1/6] Validating both regions...' -ForegroundColor Yellow
$regionAOutput = & kubectl get nodes --context biz-prod-regiona 2>&1 | Out-String
$regionBOutput = & kubectl get nodes --context biz-prod-regionb 2>&1 | Out-String

$regionAOk = $true
if ($LASTEXITCODE -ne 0) {
    $regionAOk = $false
}
if ($regionAOutput -match 'connection refused') {
    $regionAOk = $false
}

if ($regionAOk) {
    Write-Host '  [OK] region A is healthy' -ForegroundColor Green
} else {
    Write-Host '  [WARN] region A unreachable - simulation already happened' -ForegroundColor Yellow
}

if ($regionBOutput -match 'Ready') {
    $readyB = ($regionBOutput -split "`n" | Where-Object { $_ -match 'Ready' }).Count
    $bText = '  [OK] region B is healthy (' + $readyB + ' nodes Ready)'
    Write-Host $bText -ForegroundColor Green
} else {
    Write-Host '  [FAIL] region B unreachable' -ForegroundColor Red
    exit 1
}

# ---- Step 2: check ArgoCD ----
Write-Host ''
Write-Host '[2/6] Checking ArgoCD multi-cluster state...' -ForegroundColor Yellow
& kubectl config use-context ops-mgmt | Out-Null
$apps = & kubectl get applications -n argocd -l app.kubernetes.io/part-of=opshub 2>&1 | Out-String
if ($LASTEXITCODE -eq 0) {
    if ($apps -match 'checkout-api-biz-prod-regiona') {
        Write-Host '  [OK] found business app synced to region A' -ForegroundColor Green
    } else {
        Write-Host '  [WARN] no region A app found' -ForegroundColor Yellow
    }
} else {
    Write-Host '  [WARN] cannot query ArgoCD' -ForegroundColor Yellow
}

# ---- Step 3: kill region A ----
Write-Host ''
Write-Host '[3/6] Simulating region A failure...' -ForegroundColor Yellow
if ($regionAOk) {
    Write-Host '  Deleting biz-prod-regiona cluster...' -ForegroundColor Gray
    & kind delete cluster --name biz-prod-regiona 2>&1 | Out-Null
    Write-Host '  [OK] region A cluster deleted' -ForegroundColor Green
} else {
    Write-Host '  [OK] region A already in failure state' -ForegroundColor Green
}

# ---- Step 4: wait for ArgoCD detection ----
Write-Host ''
Write-Host '[4/6] Waiting for ArgoCD to detect (30s)...' -ForegroundColor Yellow
Start-Sleep -Seconds 30
$appStatus = & kubectl get application checkout-api-biz-prod-regiona -n argocd -o jsonpath='{.status.health.status}' 2>&1 | Out-String
$appStatus = $appStatus.Trim()
$statusText = '  Application Health: ' + $appStatus
if ($appStatus -eq 'Healthy') {
    Write-Host $statusText -ForegroundColor Green
} else {
    Write-Host $statusText -ForegroundColor Yellow
}

# ---- Step 5: scale region B ----
Write-Host ''
Write-Host '[5/6] Scaling region B to absorb traffic...' -ForegroundColor Yellow
& kubectl config use-context biz-prod-regionb | Out-Null
& kubectl scale deployment checkout-api -n app-checkout --replicas=10 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host '  [OK] region B checkout-api scaled to 10 replicas' -ForegroundColor Green
} else {
    Write-Host '  [WARN] scale command failed' -ForegroundColor Yellow
}

# ---- Step 6: verify business recovery ----
Write-Host ''
Write-Host '[6/6] Verifying business recovery on region B...' -ForegroundColor Yellow
Start-Sleep -Seconds 10
$testResult = $null
$testOk = $false
$testContent = ''
try {
    $testResult = Invoke-WebRequest -Uri 'http://localhost:30082/checkout/dr-test' -TimeoutSec 5 -UseBasicParsing 2>&1
    if ($testResult.StatusCode -eq 200) {
        $testOk = $true
        $testContent = $testResult.Content
    }
} catch {
    $testContent = $_.Exception.Message
}

if ($testOk) {
    Write-Host '  [OK] business recovered on region B' -ForegroundColor Green
    $respText = '  response: ' + $testContent
    Write-Host $respText -ForegroundColor Gray
} else {
    Write-Host '  [WARN] test request failed' -ForegroundColor Yellow
    $errText = '  error: ' + $testContent
    Write-Host $errText -ForegroundColor Gray
}

# ---- Summary ----
Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' [OK] DR drill demo complete' -ForegroundColor Green
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Timeline (real values vary by environment):'
Write-Host '  T+0:    fault simulated'
Write-Host '  T+30s:  ArgoCD detects region A unreachable'
Write-Host '  T+1m:   Alertmanager fires ClusterDown'
Write-Host '  T+2m:   on-call decides to failover'
Write-Host '  T+3m:   region B scale-up complete'
Write-Host '  T+3.5m: GLB shifts traffic to region B'
Write-Host '  T+5m:   full business recovery'
Write-Host ''
Write-Host 'Cleanup:'
Write-Host '  Restore region A: create-clusters.ps1' -ForegroundColor Yellow
Write-Host '  ArgoCD will auto-rediscover and re-sync' -ForegroundColor Gray

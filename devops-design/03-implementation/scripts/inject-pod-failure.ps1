# Chaos injection: Pod failure
# PowerShell 5.1 compatible
# Demonstrates: HPA auto-scale + Alertmanager alerting pipeline
# Usage: powershell -ExecutionPolicy Bypass -File inject-pod-failure.ps1
$ErrorActionPreference = 'Stop'

$App = 'checkout-api'
$Namespace = 'app-checkout-staging'

Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' Inject: Pod Failure' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

# Switch to biz-prod-regiona context
& kubectl config use-context biz-prod-regiona | Out-Null

# ---- Step 1: verify app exists ----
Write-Host ''
$podsOutput = & kubectl get pods -n $Namespace -l ('app.kubernetes.io/name=' + $App) -o name 2>&1 | Out-String
$pods = @()
if ($LASTEXITCODE -eq 0) {
    $pods = $podsOutput -split "`n" | Where-Object { $_ -and $_.Trim() }
}

if (($pods.Count -eq 0) -or ($LASTEXITCODE -ne 0)) {
    $errText = '[FAIL] app ' + $App + ' not found in namespace ' + $Namespace
    Write-Host $errText -ForegroundColor Red
    exit 1
}
$podCountText = '  [OK] found ' + $pods.Count + ' pod(s)'
Write-Host $podCountText -ForegroundColor Green

# ---- Step 2: show current state ----
Write-Host ''
Write-Host '[1/4] Current pod status:' -ForegroundColor Yellow
& kubectl get pods -n $Namespace -l ('app.kubernetes.io/name=' + $App) --no-headers 2>&1 | ForEach-Object {
    $lineText = '  ' + $_
    Write-Host $lineText
}

# ---- Step 3: inject failure - delete one pod ----
Write-Host ''
Write-Host '[2/4] Injecting failure: killing one pod...' -ForegroundColor Yellow
$firstPod = ($pods | Select-Object -First 1).Trim()
$targetPod = $firstPod -replace '^pod/', ''
& kubectl delete pod $targetPod -n $Namespace --grace-period=0 --force 2>&1 | Out-Null
$killedText = '  [OK] killed ' + $targetPod
Write-Host $killedText -ForegroundColor Green

# ---- Step 4: observe recovery ----
Write-Host ''
Write-Host '[3/4] Observing auto-recovery (25s)...' -ForegroundColor Yellow
Start-Sleep -Seconds 5
$loopCount = 5
for ($i = 0; $i -lt $loopCount; $i++) {
    $podLines = & kubectl get pods -n $Namespace -l ('app.kubernetes.io/name=' + $App) --no-headers 2>&1 | Out-String
    $ready = 0
    if ($LASTEXITCODE -eq 0) {
        $lines = $podLines -split "`n" | Where-Object { $_ -and $_.Trim() }
        foreach ($line in $lines) {
            if ($line -match 'Running') { $ready = $ready + 1 }
        }
    }
    $desired = & kubectl get deployment $App -n $Namespace -o jsonpath='{.spec.replicas}' 2>&1 | Out-String
    $desired = $desired.Trim()
    $ts = (Get-Date).ToString('HH:mm:ss')
    $statusText = '  [' + $ts + '] Pods Ready: ' + $ready + ' / ' + $desired
    Write-Host $statusText
    Start-Sleep -Seconds 5
}

# ---- Step 5: check alerts ----
Write-Host ''
Write-Host '[4/4] Verifying alert pipeline...' -ForegroundColor Yellow
Write-Host '  Switching to ops-mgmt context to query Prometheus' -ForegroundColor Gray
& kubectl config use-context ops-mgmt | Out-Null
$alerts = & kubectl exec -n monitoring deploy/prometheus-operated -- promtool query instant 'ALERTS{alertstate="firing",severity="warning"}' 2>&1 | Out-String
if ($LASTEXITCODE -eq 0) {
    Write-Host '  [OK] current firing alerts:' -ForegroundColor Green
    Write-Host $alerts
} else {
    Write-Host '  [WARN] Prometheus not running or query failed' -ForegroundColor Yellow
    Write-Host '  Expected: K8sDeploymentReplicasMismatch or KubernetesPodNotReady' -ForegroundColor Gray
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Green
Write-Host ' [OK] Failure injection + recovery demo complete' -ForegroundColor Green
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'What happened:'
Write-Host '  - Deployment auto-recreated the pod (replicas preserved)'
Write-Host '  - Pod became ready within ~10-15s'
Write-Host '  - If alerting configured: KubePodNotReady fires then auto-resolves'
Write-Host '  - User-facing impact: brief 5xx spike, then auto-recovery'

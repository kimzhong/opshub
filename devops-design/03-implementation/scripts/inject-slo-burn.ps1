# Chaos injection: SLO Burn Rate alert trigger
# PowerShell 5.1 compatible
# Demonstrates: alert trigger -> SRE response -> recovery full pipeline
# Usage: powershell -ExecutionExecutionPolicy Bypass -File inject-slo-burn.ps1
$ErrorActionPreference = 'Stop'

$App = 'checkout-api'
$Namespace = 'app-checkout-staging'
$ErrorRate = '0.5'   # 50% error rate
$LatencyMs = '2000'  # 2s latency

Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' Inject: SLO Burn Rate (Critical)' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

& kubectl config use-context biz-prod-regiona | Out-Null

# ---- Step 1: show SLO state ----
Write-Host ''
Write-Host '[1/5] Current SLO state...' -ForegroundColor Yellow
Write-Host '  Target SLO: 99.5% availability (30d window)' -ForegroundColor Gray
Write-Host '  Alert threshold: error rate > 7.2% (14.4x burn)' -ForegroundColor Gray

& kubectl get pods -n $Namespace -l ('app.kubernetes.io/name=' + $App) --no-headers 2>&1 | ForEach-Object {
    $lineText = '  ' + $_
    Write-Host $lineText
}

# ---- Step 2: inject fault ----
Write-Host ''
Write-Host '[2/5] Injecting high error rate + latency...' -ForegroundColor Yellow
$injectText = '  error_rate=' + $ErrorRate + ', latency=' + $LatencyMs + 'ms'
Write-Host $injectText -ForegroundColor Gray
& kubectl set env deployment/$App -n $Namespace ('FAILURE_RATE=' + $ErrorRate) 2>&1 | Out-Null
& kubectl set env deployment/$App -n $Namespace ('LATENCY_MS=' + $LatencyMs) 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host '  [OK] env vars set' -ForegroundColor Green
} else {
    Write-Host '  [FAIL] env var set failed' -ForegroundColor Red
    exit 1
}

# ---- Step 3: wait for rollout ----
Write-Host ''
Write-Host '[3/5] Waiting for rollout (60s)...' -ForegroundColor Yellow
& kubectl rollout status deployment/$App -n $Namespace --timeout=60s 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host '  [OK] new config effective' -ForegroundColor Green
} else {
    Write-Host '  [WARN] rollout timeout' -ForegroundColor Yellow
}

# ---- Step 4: generate traffic to trigger alerts ----
Write-Host ''
Write-Host '[4/5] Generating traffic for 2min to trigger burn rate alert...' -ForegroundColor Yellow
$endTime = (Get-Date).AddSeconds(120)
$requestCount = 0
$errorCount = 0

while ((Get-Date) -lt $endTime) {
    $url = 'http://localhost:30081/checkout/test-' + $requestCount
    $success = $false
    try {
        $response = Invoke-WebRequest -Uri $url -TimeoutSec 5 -UseBasicParsing 2>&1
        if ($response.StatusCode -ge 500) {
            $errorCount = $errorCount + 1
        } else {
            $success = $true
        }
    } catch {
        $errorCount = $errorCount + 1
    }
    $requestCount = $requestCount + 1
    if (($requestCount % 10) -eq 0) {
        $errRate = 0
        if ($requestCount -gt 0) {
            $errRate = [math]::Round(($errorCount / $requestCount) * 100, 1)
        }
        $ts = (Get-Date).ToString('HH:mm:ss')
        $statText = '  [' + $ts + '] Requests: ' + $requestCount + ', Errors: ' + $errorCount + ' (' + $errRate + '%)'
        Write-Host $statText
    }
    Start-Sleep -Milliseconds 200
}

# ---- Step 5: verify alert firing on ops-mgmt ----
Write-Host ''
Write-Host '[5/5] Verifying alert on ops-mgmt Prometheus...' -ForegroundColor Yellow
& kubectl config use-context ops-mgmt | Out-Null
$alerts = & kubectl exec -n monitoring deploy/prometheus-operated -- promtool query instant 'count by (alertname, severity) (ALERTS{alertstate="firing",severity="critical"})' 2>&1 | Out-String
if ($LASTEXITCODE -eq 0) {
    Write-Host '  [OK] current firing critical alerts:' -ForegroundColor Green
    Write-Host $alerts
} else {
    Write-Host '  [WARN] Prometheus unavailable or query failed' -ForegroundColor Yellow
    Write-Host '  Expected: CheckoutAPIAvailabilityBurnRateFast / Slow' -ForegroundColor Gray
}

# ---- Recovery ----
Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' Recovery (clearing fault)' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

& kubectl config use-context biz-prod-regiona | Out-Null
& kubectl set env deployment/$App -n $Namespace 'FAILURE_RATE=0.0' 2>&1 | Out-Null
& kubectl set env deployment/$App -n $Namespace 'LATENCY_MS=0' 2>&1 | Out-Null
& kubectl rollout status deployment/$App -n $Namespace --timeout=60s 2>&1 | Out-Null

Write-Host ''
Write-Host '[OK] fault cleared. Alert should auto-resolve within 5min.' -ForegroundColor Green
Write-Host ''
Write-Host 'Timeline:'
Write-Host '  T+0:    fault injected'
Write-Host '  T+30s:  Prometheus scrapes new metrics'
Write-Host '  T+2m:   burn rate rule fires'
Write-Host '  T+2.5m: Alertmanager routes to PagerDuty / Slack'
Write-Host '  T+5m:   SRE receives page and starts handling'
Write-Host '  T+15m:  SRE fixes, alert auto-resolves'

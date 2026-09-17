# ArgoCD install script
# PowerShell 5.1 compatible
# Deploys ArgoCD to the ops-mgmt cluster
# Usage: powershell -ExecutionPolicy Bypass -File install-argocd.ps1
#
# Note: All kubectl/helm calls are wrapped in `cmd /c` to avoid PowerShell
# NativeCommandError when commands write to stderr (PS 5.1 quirk). The
# trailing `& exit /b %errorlevel%` propagates the inner exit code back to PS.
$ErrorActionPreference = 'Stop'

$ArgocdVersion = 'v2.11.0'
$ArgocdNs = 'argocd'
$PortForwardLocal = 30443

# Helper: run external command via cmd to bypass PS NativeCommandError.
# Returns the combined stdout+stderr as a string and sets $LASTEXITCODE
# to the inner command's exit code.
function Invoke-External {
    param([string]$Command)
    $out = cmd /c ($Command + ' 2>&1 & exit /b %errorlevel%')
    return $out
}

Write-Host '========================================' -ForegroundColor Cyan
Write-Host (' Installing ArgoCD ' + $ArgocdVersion) -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

# Switch to ops-mgmt context
$null = Invoke-External 'kubectl config use-context ops-mgmt'

# ---- Step 1: create namespace ----
Write-Host ''
Write-Host '[1/4] Creating namespace...' -ForegroundColor Yellow
$null = Invoke-External ('kubectl create namespace ' + $ArgocdNs + ' --dry-run=client -o yaml | kubectl apply -f -')
if ($LASTEXITCODE -eq 0) {
    Write-Host ('  [OK] namespace ' + $ArgocdNs) -ForegroundColor Green
} else {
    Write-Host '  [FAIL] namespace creation failed' -ForegroundColor Red
    exit 1
}

# ---- Step 2: install ArgoCD manifests ----
Write-Host '[2/4] Installing ArgoCD manifests (this may take 1-2 min)...' -ForegroundColor Yellow
$installUrl = ('https://raw.githubusercontent.com/argoproj/argo-cd/' + $ArgocdVersion + '/manifests/install.yaml')
$applyOut = Invoke-External ('kubectl apply -n ' + $ArgocdNs + ' -f ' + $installUrl)
if ($LASTEXITCODE -ne 0) {
    Write-Host '  [FAIL] apply failed (check network)' -ForegroundColor Red
    Write-Host $applyOut
    exit 1
}
Write-Host '  [OK] manifests applied' -ForegroundColor Green

# ---- Step 3: wait for ready ----
Write-Host '[3/4] Waiting for ArgoCD to be ready (timeout 300s)...' -ForegroundColor Yellow
$null = Invoke-External ('kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n ' + $ArgocdNs)
$null = Invoke-External ('kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n ' + $ArgocdNs)
$null = Invoke-External ('kubectl wait --for=condition=available --timeout=300s deployment/argocd-application-controller -n ' + $ArgocdNs)
if ($LASTEXITCODE -ne 0) {
    Write-Host '  [FAIL] wait failed' -ForegroundColor Red
    exit 1
}
Write-Host '  [OK] all components ready' -ForegroundColor Green

# ---- Step 4: start port-forward ----
Write-Host '[4/4] Starting port-forward (background)...' -ForegroundColor Yellow
Write-Host ('  Forwarding to local port ' + $PortForwardLocal + ' ...') -ForegroundColor Gray

$existing = Get-NetTCPConnection -LocalPort $PortForwardLocal -ErrorAction SilentlyContinue
if (-not $existing) {
    $jobScript = {
        param($ns, $port)
        cmd /c ('kubectl port-forward svc/argocd-server -n ' + $ns + ' ' + $port + ':443 --address 0.0.0.0 2>&1 & exit /b %errorlevel%')
    }
    Start-Job -ScriptBlock $jobScript -ArgumentList $ArgocdNs, $PortForwardLocal | Out-Null
    Start-Sleep -Seconds 3
    Write-Host ('  [OK] port-forward started') -ForegroundColor Green
} else {
    Write-Host ('  [WARN] port ' + $PortForwardLocal + ' already in use, skipping') -ForegroundColor Yellow
}

# ---- Final: print access info ----
Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' [OK] ArgoCD installation complete' -ForegroundColor Green
Write-Host '========================================' -ForegroundColor Cyan

$initialPassword = ''
$secretJson = Invoke-External ('kubectl -n ' + $ArgocdNs + ' get secret argocd-initial-admin-secret -o jsonpath={.data.password}')
$secretJson = $secretJson.Trim()
if ($secretJson) {
    try {
        $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secretJson))
        $initialPassword = $decoded
    } catch {
        $initialPassword = '(decode failed: ' + $secretJson + ')'
    }
}

Write-Host ''
Write-Host 'Access info:'
Write-Host ('  URL: https://localhost:' + $PortForwardLocal) -ForegroundColor White
Write-Host '  Username: admin'
Write-Host ('  Password: ' + $initialPassword) -ForegroundColor Yellow
Write-Host ''
Write-Host 'Next steps:'
Write-Host '  1. Apply App of Apps: kubectl apply -f apps/root-app.yaml' -ForegroundColor Yellow
Write-Host ('  2. Open Web UI: https://localhost:' + $PortForwardLocal) -ForegroundColor Yellow
Write-Host ''
Write-Host 'Or use CLI:'
$cliCmd = 'argocd login localhost:' + $PortForwardLocal + ' --username admin --password "' + $initialPassword + '" --insecure'
Write-Host ('  ' + $cliCmd) -ForegroundColor Gray

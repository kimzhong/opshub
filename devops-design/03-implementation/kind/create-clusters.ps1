# kind multi-cluster bootstrap script
# PowerShell 5.1 compatible (tested with PS 5.1.19041)
# Purpose: create ops-mgmt + 2 biz clusters for OpsHub platform
# Prereq: Docker running, kind + kubectl installed
# Usage: powershell -ExecutionPolicy Bypass -File create-clusters.ps1
$ErrorActionPreference = 'Stop'

# PS5.1 safe: $PSScriptRoot is available in scripts, not modules
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptDir) { $ScriptDir = $PSScriptRoot }
$ClustersDir = Join-Path $ScriptDir 'clusters'
$LogDir = Join-Path $ScriptDir 'logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }

Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' OpsHub Multi-Cluster Bootstrap' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

# ---- Step 1: preflight checks ----
Write-Host ''
Write-Host '[1/5] Checking prerequisites...' -ForegroundColor Yellow
$preflightOk = $true

# Check kind
try {
    $kindVersion = & kind version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host ('  [OK] kind: ' + $kindVersion) -ForegroundColor Green
    } else {
        Write-Host '  [FAIL] kind not installed. Get it from https://kind.sigs.k8s.io/' -ForegroundColor Red
        $preflightOk = $false
    }
} catch {
    Write-Host '  [FAIL] kind not installed. Get it from https://kind.sigs.k8s.io/' -ForegroundColor Red
    $preflightOk = $false
}

# Check docker
try {
    $dockerVersion = & docker version --format '{{.Server.Version}}' 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host ('  [OK] Docker: ' + $dockerVersion) -ForegroundColor Green
    } else {
        Write-Host '  [FAIL] Docker not running. Please start Docker Desktop' -ForegroundColor Red
        $preflightOk = $false
    }
} catch {
    Write-Host '  [FAIL] Docker not running. Please start Docker Desktop' -ForegroundColor Red
    $preflightOk = $false
}

# Check kubectl
try {
    # kubectl 1.30+ removed --short; use full --client and trim
    $kubectlFull = & kubectl version --client 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        $ver = ($kubectlFull -split "`n" | Select-String -Pattern 'Client Version' | Select-Object -First 1) -replace '.*v(\d+\.\d+\.\d+).*', '$1'
        if (-not $ver) { $ver = ($kubectlFull -split "`n" | Select-Object -First 1).Trim() }
        Write-Host ('  [OK] kubectl ' + $ver) -ForegroundColor Green
    } else {
        Write-Host '  [FAIL] kubectl not installed' -ForegroundColor Red
        $preflightOk = $false
    }
} catch {
    Write-Host '  [FAIL] kubectl not installed' -ForegroundColor Red
    $preflightOk = $false
}

if (-not $preflightOk) {
    Write-Host ''
    Write-Host '[FAIL] Pre-flight failed. Fix the issues above and retry.' -ForegroundColor Red
    exit 1
}

# ---- Step 2: create clusters ----
Write-Host ''
Write-Host '[2/5] Creating 3 Kubernetes clusters...' -ForegroundColor Yellow
$clusters = @('ops-mgmt', 'biz-prod-regiona', 'biz-prod-regionb')
# Get existing clusters (call via cmd to avoid PS NativeCommandError on stderr)
$existingOut = cmd /c 'kind get clusters 2>&1 & exit /b %errorlevel%'
$existingList = @()
if ($LASTEXITCODE -eq 0) {
    $existingList = $existingOut -split "`r?`n" | Where-Object { $_ -and $_.Trim() }
}
foreach ($c in $clusters) {
    $configFile = Join-Path $ClustersDir ($c + '.yaml')
    if ($existingList -contains $c) {
        Write-Host ('  -> ' + $c + ' [SKIP] already exists') -ForegroundColor Yellow
        continue
    }
    Write-Host ('  -> creating ' + $c + ' ...') -NoNewline
    $output = cmd /c ('kind create cluster --config "' + $configFile + '" 2>&1 & exit /b %errorlevel%')
    if ($LASTEXITCODE -eq 0) {
        Write-Host ' [OK]' -ForegroundColor Green
    } else {
        Write-Host ' [FAIL]' -ForegroundColor Red
        Write-Host $output
        exit 1
    }
}

# ---- Step 3: rename contexts ----
Write-Host ''
Write-Host '[3/5] Renaming kubectl contexts...' -ForegroundColor Yellow
$contexts = @('ops-mgmt', 'biz-prod-regiona', 'biz-prod-regionb')
foreach ($ctx in $contexts) {
    $oldName = ('kind-' + $ctx)
    & kubectl config rename-context $oldName $ctx 2>&1 | Out-Null
    Write-Host ('  [OK] ' + $ctx) -ForegroundColor Green
}

# ---- Step 4: verify cluster health ----
Write-Host ''
Write-Host '[4/5] Verifying cluster health...' -ForegroundColor Yellow
foreach ($ctx in $contexts) {
    Write-Host ('  -> ' + $ctx + ' ...') -NoNewline
    $jsonOutput = & kubectl --context $ctx get nodes -o json 2>&1 | Out-String
    $readyCount = 0
    $totalCount = 0
    if ($LASTEXITCODE -eq 0) {
        try {
            $nodes = $jsonOutput | ConvertFrom-Json
            if ($nodes -and $nodes.items) {
                $totalCount = $nodes.items.Count
                foreach ($node in $nodes.items) {
                    $isReady = $false
                    if ($node.status.conditions) {
                        foreach ($cond in $node.status.conditions) {
                            if (($cond.type -eq 'Ready') -and ($cond.status -eq 'True')) {
                                $isReady = $true
                                break
                            }
                        }
                    }
                    if ($isReady) { $readyCount = $readyCount + 1 }
                }
            }
        } catch {
            # parse error, leave counts at 0
        }
    }
    if (($readyCount -eq $totalCount) -and ($totalCount -gt 0)) {
        $statusText = (' OK (' + $readyCount + '/' + $totalCount + ' Ready)')
        Write-Host $statusText -ForegroundColor Green
    } else {
        $statusText = (' FAIL (' + $readyCount + '/' + $totalCount + ' Ready)')
        Write-Host $statusText -ForegroundColor Red
    }
}

# ---- Step 5: install MetalLB ----
Write-Host ''
Write-Host '[5/5] Installing MetalLB on each cluster...' -ForegroundColor Yellow
$metallbUrl = 'https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml'
foreach ($ctx in $contexts) {
    Write-Host ('  -> ' + $ctx + ' ...') -NoNewline
    & kubectl --context $ctx apply -f $metallbUrl 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host ' [OK]' -ForegroundColor Green
    } else {
        Write-Host ' [WARN] (may need network access)' -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' [OK] All clusters created' -ForegroundColor Green
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Available contexts:'
foreach ($ctx in $contexts) {
    Write-Host ('  ' + $ctx)
}
Write-Host ''
Write-Host 'Next steps:'
Write-Host '  1. Deploy ArgoCD: deploy-argocd.ps1' -ForegroundColor Yellow
Write-Host '  2. Deploy observability stack' -ForegroundColor Yellow
Write-Host '  3. Deploy demo application' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Cleanup: delete-clusters.ps1' -ForegroundColor DarkGray

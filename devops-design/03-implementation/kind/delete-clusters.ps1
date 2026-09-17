# kind multi-cluster teardown script
# PowerShell 5.1 compatible
# WARNING: this deletes all kind clusters - data is unrecoverable
# Usage: powershell -ExecutionPolicy Bypass -File delete-clusters.ps1
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptDir) { $ScriptDir = $PSScriptRoot }

Write-Host '========================================' -ForegroundColor Red
Write-Host ' WARNING: deleting all kind clusters' -ForegroundColor Red
Write-Host '========================================' -ForegroundColor Red
$confirm = Read-Host ''
Write-Host 'Confirm delete? (yes/no): ' -NoNewline
$confirm = Read-Host
if ($confirm -ne 'yes') {
    Write-Host 'Cancelled' -ForegroundColor Yellow
    exit 0
}

$clusters = @('biz-prod-regionb', 'biz-prod-regiona', 'ops-mgmt')
foreach ($c in $clusters) {
    Write-Host ('  -> deleting ' + $c + ' ...') -NoNewline
    & kind delete cluster --name $c 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host ' [OK]' -ForegroundColor Green
    } else {
        Write-Host ' [SKIP] (not present)' -ForegroundColor Yellow
    }
}

# Clean up contexts
foreach ($c in $clusters) {
    & kubectl config delete-context $c 2>&1 | Out-Null
}

Write-Host ''
Write-Host '[OK] All clusters cleaned up' -ForegroundColor Green

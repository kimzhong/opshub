# Onboard new cluster helper
# PowerShell 5.1 compatible
# Placeholder: real implementation uses Terraform + ArgoCD
# Usage: powershell -ExecutionPolicy Bypass -File onboard-new-cluster.ps1 -ClusterName <name> -Region <regiona|regionb>
$ErrorActionPreference = 'Stop'

param(
    [Parameter(Mandatory = $false)]
    [string]$ClusterName,
    [Parameter(Mandatory = $false)]
    [string]$Region
)

Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' Onboard New Cluster' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

if (-not $ClusterName) {
    Write-Host 'Usage: onboard-new-cluster.ps1 -ClusterName <name> -Region <regiona|regionb>' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Example:'
    Write-Host '  onboard-new-cluster.ps1 -ClusterName biz-prod-regionc -Region regionb' -ForegroundColor Gray
    exit 1
}

if (($Region -ne 'regiona') -and ($Region -ne 'regionb')) {
    Write-Host ('[FAIL] region must be regiona or regionb, got: ' + $Region) -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host ('Onboarding cluster: ' + $ClusterName + ' into ' + $Region) -ForegroundColor Cyan
Write-Host ''
Write-Host 'This is a placeholder. Real flow:'
Write-Host '  1. Add cluster to Terraform vars (terraform/eks.tf)' -ForegroundColor Yellow
Write-Host '  2. terraform apply to create the EKS cluster + IAM' -ForegroundColor Yellow
Write-Host '  3. Add cluster context to ops-mgmt kubeconfig' -ForegroundColor Yellow
Write-Host '  4. Register cluster in ArgoCD (argocd cluster add)' -ForegroundColor Yellow
Write-Host '  5. Add Application to apps/argocd.yaml ApplicationSet' -ForegroundColor Yellow
Write-Host '  6. Commit + push, ArgoCD picks it up via GitOps' -ForegroundColor Yellow
Write-Host ''
Write-Host 'See docs/部署手册.md for the full onboarding runbook.' -ForegroundColor Gray
exit 0

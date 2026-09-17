# Cosign + Kyverno image signing setup
# PowerShell 5.1 compatible
# CI side: cosign sign --key cosign.key <image>
# K8s admission side: Kyverno verifyImage using public key
# Usage: powershell -ExecutionPolicy Bypass -File setup-cosign.ps1
$ErrorActionPreference = 'Stop'

Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' Cosign + Kyverno Image Signing Setup' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

# ---- Step 1: preflight ----
Write-Host ''
Write-Host '[1/4] Checking prerequisites...' -ForegroundColor Yellow
$cosignPath = Get-Command cosign -ErrorAction SilentlyContinue
if ($cosignPath) {
    $cosignVersion = & cosign version 2>&1 | Select-Object -First 1
    $verText = '  [OK] cosign: ' + $cosignVersion
    Write-Host $verText -ForegroundColor Green
} else {
    Write-Host '  [WARN] cosign not installed. Get it from https://docs.sigstore.dev/cosign/installation/' -ForegroundColor Yellow
}

# ---- Step 2: generate keypair ----
Write-Host ''
Write-Host '[2/4] Generating Cosign keypair...' -ForegroundColor Yellow
$keyDir = Join-Path $PSScriptRoot 'keys'
if (-not (Test-Path $keyDir)) { New-Item -ItemType Directory -Force -Path $keyDir | Out-Null }

$privKey = Join-Path $keyDir 'cosign.key'
$pubKey = Join-Path $keyDir 'cosign.pub'

if (-not (Test-Path $privKey)) {
    Write-Host '  -> generating new keypair...'
    if ($cosignPath) {
        Push-Location $keyDir
        try {
            & cosign generate-key-pair 2>&1 | Out-Null
        } finally {
            Pop-Location
        }
        if ($LASTEXITCODE -eq 0) {
            $keyDirText = '  [OK] keys generated in ' + $keyDir
            Write-Host $keyDirText -ForegroundColor Green
        } else {
            Write-Host '  [FAIL] cosign generate-key-pair failed' -ForegroundColor Red
        }
    } else {
        Write-Host '  [WARN] cosign not installed. Manual steps:' -ForegroundColor Yellow
        Write-Host '    cosign generate-key-pair' -ForegroundColor Gray
    }
} else {
    $keyDirText = '  [OK] keys already exist: ' + $keyDir
    Write-Host $keyDirText -ForegroundColor Green
}

# ---- Step 3: create K8s secret for public key ----
Write-Host ''
Write-Host '[3/4] Creating K8s secret with public key...' -ForegroundColor Yellow
& kubectl --context ops-mgmt create namespace kyverno --dry-run=client -o yaml | & kubectl apply -f - 2>&1 | Out-Null

if (Test-Path $pubKey) {
    $secretYaml = & kubectl --context ops-mgmt create secret generic cosign-public-key --namespace kyverno --from-file=('cosign.pub=' + $pubKey) --dry-run=client -o yaml 2>&1 | Out-String
    $secretYaml | & kubectl --context ops-mgmt apply -f - 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host '  [OK] public key secret created' -ForegroundColor Green
    } else {
        Write-Host '  [FAIL] secret creation failed' -ForegroundColor Red
    }
} else {
    Write-Host '  [WARN] public key not found, skipping secret creation' -ForegroundColor Yellow
}

# ---- Step 4: deploy Kyverno ----
Write-Host ''
Write-Host '[4/4] Deploying Kyverno...' -ForegroundColor Yellow
$kyvernoRepo = 'https://kyverno.github.io/kyverno'
& helm --kube-context ops-mgmt repo add kyverno $kyvernoRepo 2>&1 | Out-Null
& helm --kube-context ops-mgmt repo update 2>&1 | Out-Null

& helm --kube-context ops-mgmt upgrade --install kyverno kyverno/kyverno --namespace kyverno --create-namespace --set replicaCount=3 --set backgroundController.enabled=true --set cleanupController.enabled=true --wait 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host '  [OK] Kyverno deployed' -ForegroundColor Green
} else {
    Write-Host '  [WARN] helm install may have issues, check with helm list' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' [OK] Cosign + Kyverno deployment complete' -ForegroundColor Green
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Next steps:'
Write-Host '  1. Apply policies: kubectl apply -f policies/' -ForegroundColor Yellow
Write-Host '  2. Test signing: cosign sign --key keys/cosign.key <image>' -ForegroundColor Yellow
Write-Host '  3. Test verify:  cosign verify --key keys/cosign.pub <image>' -ForegroundColor Yellow

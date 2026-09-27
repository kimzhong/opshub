Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
$result = lark-cli docs +create --title "Kind多集群环境使用手册" --doc-format markdown --content @"
C:\Users\kim\kind-env\feishu_content_tmp.txt
"@ 2>&1
Write-Host "EXIT: $LASTEXITCODE"
Write-Host $result

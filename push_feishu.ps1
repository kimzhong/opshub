$ErrorActionPreference = 'Stop'
$mdFile = Get-ChildItem 'C:\Users\kim\kind-env\' -Filter '使用手册.md' | Select-Object -First 1
$content = Get-Content -Path $mdFile.FullName -Raw -Encoding UTF8
$content | Out-File -FilePath 'C:\Users\kim\kind-env\feishu_content_tmp.txt' -Encoding UTF8
Write-Host "Written $($content.Length) chars"

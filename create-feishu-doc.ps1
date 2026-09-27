$ErrorActionPreference = 'Stop'
$content = Get-Content -Path 'C:\Users\kim\kind-env\feishu-doc.md' -Raw -Encoding UTF8
$title = 'Kind 多集群本地开发环境 - 使用指南'
lark-cli docs +create --as user --title $title --content $content --doc-format markdown

$ErrorActionPreference = 'Stop'
$content = Get-Content -Path 'C:\Users\kim\kind-env\feishu-e2e-doc.md' -Raw -Encoding UTF8
$title = 'Kind 多集群端到端 DevOps 演示环境'
lark-cli docs +create --as user --title $title --content $content --doc-format markdown

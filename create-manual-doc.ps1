$ErrorActionPreference = 'Stop'
$content = [System.IO.File]::ReadAllText('C:\Users\kim\kind-env\_manual_short.md', [System.Text.Encoding]::UTF8)
$title = 'Kind 多集群环境 - 完整使用手册'
lark-cli docs +create --as user --title $title --content $content --doc-format markdown

\Continue = 'Stop'
\ = [System.IO.File]::ReadAllText('C:\Users\kim\kind-env\fault-doc-body.md', [System.Text.Encoding]::UTF8)
\ = [System.IO.File]::ReadAllText('C:\Users\kim\kind-env\fault-title.txt', [System.Text.Encoding]::UTF8).Trim()
lark-cli docs +create --as user --title \ --content \ --doc-format markdown

# -*- coding: utf-8 -*-
"""Push the Kind env user manual to Feishu Docs."""
import subprocess, sys, json, re, os

os.chdir(r"C:\Users\kim\kind-env")

MANUAL = r"C:\Users\kim\kind-env\使用手册.md"
TMP_CONTENT = r"feishu_manual_src.md"

import shutil
shutil.copy(MANUAL, TMP_CONTENT)
print(f"Copied to {TMP_CONTENT}")

# Build the lark-cli command
# --content @file syntax: lark-cli reads the file directly; MUST be relative path
result = subprocess.run(
    [
        r"C:\Users\kim\AppData\Roaming\npm\lark-cli.cmd", "docs", "+create",
        "--title", "Kind多集群环境使用手册",
        "--doc-format", "markdown",
        "--content", f"@{TMP_CONTENT}",
    ],
    capture_output=True,
    text=False,  # get bytes, handle encoding ourselves
)

stdout = result.stdout.decode("utf-8", errors="replace")
stderr = result.stderr.decode("utf-8", errors="replace")

print(f"Exit code: {result.returncode}")
print(f"STDOUT:\n{stdout[:3000]}")
if stderr:
    print(f"STDERR:\n{stderr[:1000]}")

# Try to parse JSON response for document token
try:
    data = json.loads(stdout.strip())
    if isinstance(data, list) and len(data) > 0:
        data = data[0]
    doc_token = data.get("document", {}).get("document_id") or data.get("document_id") or data.get("token")
    if doc_token:
        print(f"\n✅ Document created! Token: {doc_token}")
        print(f"🔗 https://my.feishu.cn/docx/{doc_token}")
    else:
        print("\nResponse data:", json.dumps(data, ensure_ascii=False, indent=2))
except Exception as e:
    print(f"\nParse error: {e}")
    print("Raw output:", stdout[:500])

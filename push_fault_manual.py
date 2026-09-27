# -*- coding: utf-8 -*-
"""Push the fault scenario manual to Feishu Docs."""
import subprocess, json, os

os.chdir(r"C:\Users\kim\kind-env")

FAULT = r"C:\Users\kim\kind-env\故障场景与响应手册.md"

import shutil
shutil.copy(FAULT, "feishu_fault_src.md")

result = subprocess.run(
    [
        r"C:\Users\kim\AppData\Roaming\npm\lark-cli.cmd", "docs", "+create",
        "--title", "Kind集群故障场景与响应手册",
        "--doc-format", "markdown",
        "--content", "@feishu_fault_src.md",
    ],
    capture_output=True,
    text=False,
)

stdout = result.stdout.decode("utf-8", errors="replace")
stderr = result.stderr.decode("utf-8", errors="replace")

print(f"Exit: {result.returncode}")
print(f"STDOUT:\n{stdout[:2000]}")
if stderr:
    print(f"STDERR:\n{stderr[:500]}")

try:
    data = json.loads(stdout.strip())
    if data.get("ok"):
        doc = data["data"]["document"]
        print(f"\n✅ 故障手册创建成功!")
        print(f"🔗 {doc['url']}")
    else:
        print(f"\n❌ Error: {data}")
except Exception as e:
    print(f"Parse error: {e}")

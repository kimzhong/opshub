# -*- coding: utf-8 -*-
"""Push the screenshot guide HTML to Feishu as a converted markdown document."""
import subprocess, json, os

os.chdir(r"C:\Users\kim\kind-env")

# Convert HTML -> simple Markdown for Feishu
import re

with open(r"C:\Users\kim\kind-env\使用手册截图版.html", "r", encoding="utf-8") as f:
    html = f.read()

# Strip HTML tags but keep structure
md = re.sub(r'<style.*?</style>', '', html, flags=re.DOTALL)
md = re.sub(r'<nav>.*?</nav>', '', md, flags=re.DOTALL)
md = re.sub(r'<svg.*?</svg>', '[Architecture Diagram — see HTML version]', md, flags=re.DOTALL)
md = re.sub(r'<[^>]+>', '', md)
md = re.sub(r'\[SCREENSHOT\]', '## [SCREENSHOT]', md)
md = re.sub(r'\n{3,}', '\n\n', md)
md = md.strip()

with open("feishu_screenshot_src.md", "w", encoding="utf-8") as f:
    f.write(md)

print(f"Markdown: {len(md)} chars")

result = subprocess.run(
    [r"C:\Users\kim\AppData\Roaming\npm\lark-cli.cmd", "docs", "+create",
     "--title", "Kind多集群环境使用手册-截图版",
     "--doc-format", "markdown",
     "--content", "@feishu_screenshot_src.md"],
    capture_output=True, text=False
)

stdout = (result.stdout or b"").decode("utf-8", errors="replace")
try:
    data = json.loads(stdout.strip())
    if data.get("ok"):
        doc = data["data"]["document"]
        print(f"\nSUCCESS! Doc: {doc['document_id']}")
        print(f"URL: {doc['url']}")
    else:
        print(f"Error: {data}")
except Exception as e:
    print(f"Parse error: {e}")
    print("Raw:", stdout[:500])

# -*- coding: utf-8 -*-
import os
d = r"C:\Users\kim\kind-env"
for f in os.listdir(d):
    if "html" in f or "手册" in f or "manual" in f.lower() or "使用" in f:
        path = os.path.join(d, f)
        size = os.path.getsize(path)
        print(f"{f}: {size:,} bytes")

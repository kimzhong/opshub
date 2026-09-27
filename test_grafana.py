# -*- coding: utf-8 -*-
import urllib.request, socket, time

# Test connectivity
for port, name in [(30300, 'Grafana'), (30080, 'ArgoCD')]:
    try:
        s = socket.socket()
        s.settimeout(3)
        s.connect(('127.0.0.1', port))
        s.close()
        print(f'{name} on 127.0.0.1:{port}: ALIVE')
    except Exception as e:
        print(f'{name} on 127.0.0.1:{port}: DEAD - {e}')

    # Also try WSL IP
    try:
        s2 = socket.socket()
        s2.settimeout(3)
        s2.connect(('172.30.156.99', port))
        s2.close()
        print(f'{name} on WSL-IP:{port}: ALIVE')
    except Exception as e:
        print(f'{name} on WSL-IP:{port}: DEAD - {e}')

# Try HTTP request
for host in ['http://127.0.0.1:30300', 'http://172.30.156.99:30300']:
    try:
        req = urllib.request.urlopen(host, timeout=5)
        data = req.read(200).decode()
        print(f'HTTP {host}: OK, title={data[data.find("<title>")+7:data.find("</title>")] if "<title>" in data else "no title"}')
    except Exception as e:
        print(f'HTTP {host}: FAIL - {e}')

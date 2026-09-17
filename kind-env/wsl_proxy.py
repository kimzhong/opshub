# -*- coding: utf-8 -*-
"""Lightweight HTTP proxy: listens on Windows localhost, forwards to WSL2 Kind services.
   Run with: python wsl_proxy.py
   Then browser can access localhost:30300 (Grafana), localhost:30080 (ArgoCD)
"""
import socket, threading, time

WSL_IP = "172.30.156.99"
PORTS = {
    30300: ("Grafana", 30300),
    30080: ("ArgoCD", 30080),
}

def handle(client, wsl_ip, wsl_port, name):
    try:
        server = socket.create_connection((wsl_ip, wsl_port), timeout=10)
        print(f"[proxy] {name} {client.getpeername()} <-> {wsl_ip}:{wsl_port}")
        def forward(src, dst):
            try:
                while True:
                    data = src.recv(8192)
                    if not data: break
                    dst.sendall(data)
            except: pass
            finally:
                try: src.close()
                except: pass
                try: dst.close()
                except: pass
        t1 = threading.Thread(target=forward, args=(client, server), daemon=True)
        t2 = threading.Thread(target=forward, args=(server, client), daemon=True)
        t1.start(); t2.start()
    except Exception as e:
        print(f"[proxy] {name} error: {e}")
        client.close()

def listen(port, wsl_ip, wsl_port, name):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", port))
    s.listen(50)
    print(f"[proxy] Listening on 127.0.0.1:{port} -> {wsl_ip}:{wsl_port} ({name})")
    while True:
        client, _ = s.accept()
        threading.Thread(target=handle, args=(client, wsl_ip, wsl_port, name), daemon=True).start()

print(f"[proxy] WSL2 IP detected: {WSL_IP}")
print("[proxy] Make sure kubectl port-forward is running in WSL2:")
print(f"[proxy]   wsl -d Ubuntu kubectl -n monitoring port-forward svc/prometheus-grafana 30300:80 --address {WSL_IP}")
print(f"[proxy]   wsl -d Ubuntu kubectl -n argocd port-forward svc/argocd-server 30080:443 --address {WSL_IP}")
print("[proxy] Starting proxies...")
for port, (name, wsl_port) in PORTS.items():
    t = threading.Thread(target=listen, args=(port, WSL_IP, wsl_port, name), daemon=True)
    t.start()
    time.sleep(0.2)
print("[proxy] All proxies running. Press Ctrl+C to stop.")
while True:
    time.sleep(1)

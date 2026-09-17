# -*- coding: utf-8 -*-
"""Simple proxy: localhost:30082 -> WSL2 ArgoCD(30081), localhost:30302 -> WSL2 Grafana(30301)"""
import http.server, socketserver, urllib.request, urllib.error, threading

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            if ':30082' in self.headers.get('Host','') or self.path.startswith('/argocd'):
                target = 'http://127.0.0.1:30081' + self.path.replace('/argocd','')
            else:
                target = 'http://127.0.0.1:30301' + self.path.replace('/grafana','')
            req = urllib.request.Request(target, headers={k:v for k,v in self.headers.items() if k.lower()!='host'}, method=self.command)
            resp = urllib.request.urlopen(req, timeout=10)
            self.send_response(resp.status)
            for k,v in resp.headers.items():
                if k.lower() not in ('transfer-encoding','connection','content-encoding'):
                    self.send_header(k, v)
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(resp.read())
        except Exception as ex:
            self.send_response(502); self.end_headers()
            self.wfile.write(str(ex).encode())

    do_POST = do_GET; do_PUT = do_GET; do_DELETE = do_GET; do_PATCH = do_GET
    def log_message(self, fmt, *a): print(f'[proxy] {fmt%a}')

srv = socketserver.ThreadingMixIn(http.server.HTTPServer)
for port, name in [(30082,'argocd→WSL:30081'),(30302,'grafana→WSL:30301')]:
    try:
        s = srv(('127.0.0.1', port), H)
        s.allow_reuse_address = True
        t = threading.Thread(target=s.serve_forever, daemon=True)
        t.start()
        print(f'[proxy] http://127.0.0.1:{port} -> {name}')
    except Exception as ex:
        print(f'[proxy] port {port} error: {ex}')
print('[proxy] Running. Close this window to stop.')
s.serve_forever()

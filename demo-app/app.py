"""
Demo application: Node.js + Flask-like Python health service
Exposes /health, /metrics, /ready endpoints for K8s probes + Prometheus scraping.
"""

import os
import sys
import time
import json
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

VERSION = os.environ.get("APP_VERSION", "v1.0.0")
REPLICAS = os.environ.get("REPLICAS", "1")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "production")
START_TIME = time.time()

class DemoHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "version": VERSION}).encode())
        elif self.path == "/ready":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"ready": True}).encode())
        elif self.path == "/metrics":
            uptime = time.time() - START_TIME
            metrics = [
                f'app_info{{version="{VERSION}",environment="{ENVIRONMENT}"}} 1',
                f'app_uptime_seconds{{version="{VERSION}"}} {uptime:.2f}',
                f'app_requests_total{{version="{VERSION}"}} {int(uptime * 3.7)}',
            ]
            body = "\n".join(metrics) + "\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body.encode())
        elif self.path == "/":
            body = f"Demo App {VERSION} | Environment: {ENVIRONMENT} | Replicas: {REPLICAS}"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body.encode())
        else:
            self.send_response(404)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": "not found"}).encode())

    def log_message(self, format, *args):
        print(f"[{datetime.now().isoformat()}] {args[0]}")

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    print(f"Starting Demo App {VERSION} on port {port}")
    server = HTTPServer(("0.0.0.0", port), DemoHandler)
    server.serve_forever()

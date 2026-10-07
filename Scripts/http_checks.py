#!/usr/bin/env python3
"""Local camera fixture; no real camera, credentials or external network involved."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
import json, subprocess, sys, threading, time
ORIGINAL = b'\xff\xd8EXIF-preservation-fixture\xff\xd9'
class Camera(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *_): pass
    def handle(self):
        try: super().handle()
        except (BrokenPipeError, ConnectionResetError): pass
    def do_GET(self):
        url = urlparse(self.path); query = parse_qs(url.query)
        code, payload = 200, b''
        if url.path == '/v1/props': payload = json.dumps({'model':'RICOH GR IV','serialNo':'TEST-0001','firmwareVersion':'fixture'}).encode()
        elif url.path == '/v1/photos':
            if query.get('storage') != ['in']: code = 400
            payload = json.dumps({'dirs':[{'name':'100RICOH','files':['R001.JPG','R001.DNG']}]}).encode()
        elif url.path.endswith('/REDIRECT.JPG'):
            self.send_response(302); self.send_header('Location','http://127.0.0.1:1/no-redirect'); self.send_header('Content-Length','0'); self.end_headers(); return
        elif url.path.endswith('/TRUNCATED.JPG'):
            self.send_response(200); self.send_header('Content-Length','99999'); self.send_header('Connection','close'); self.end_headers(); self.wfile.write(ORIGINAL); self.close_connection=True; return
        elif url.path.endswith('/ERROR.JPG'): code, payload = 503, b'camera busy'
        elif url.path.endswith('/SLOW.JPG'):
            self.send_response(200); self.send_header('Content-Length','100000'); self.end_headers()
            try:
                for _ in range(100): self.wfile.write(b'x'*1000); self.wfile.flush(); time.sleep(.03)
            except (BrokenPipeError,ConnectionResetError): pass
            return
        elif url.path.endswith('/R001.JPG'):
            if 'size' in query: code, payload = 400, b'resizing forbidden in original test'
            else: payload = ORIGINAL
        else: code, payload = 404, b'not found'
        self.send_response(code); self.send_header('Content-Length',str(len(payload))); self.end_headers(); self.wfile.write(payload)
server=ThreadingHTTPServer(('127.0.0.1',0),Camera)
threading.Thread(target=server.serve_forever,daemon=True).start()
try: result=subprocess.run([sys.argv[1],str(server.server_port)]).returncode
finally: server.shutdown(); server.server_close()
sys.exit(result)

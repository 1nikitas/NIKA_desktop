"""Local-only XCTest fixture: /model.gguf ignores Range, /range honors it; content is abc."""
from http.server import HTTPServer, BaseHTTPRequestHandler
class Handler(BaseHTTPRequestHandler):
 def do_GET(self):
  data=b'abc'
  if 'range' in self.path:
   start=int(self.headers.get('Range','bytes=0-').split('=')[1].split('-')[0])
   if start>=len(data):
    self.send_response(416);self.end_headers();return
   self.send_response(206);self.send_header('Content-Range',f'bytes {start}-{len(data)-1}/{len(data)}');data=data[start:]
  else:self.send_response(200)
  self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
 def log_message(self,*args):pass
HTTPServer(('127.0.0.1',18283),Handler).serve_forever()

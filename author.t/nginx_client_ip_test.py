"""Exercise the generated ingress header against an owned HTTP upstream."""
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import json
import re
import shutil
import socket
import subprocess
import tempfile
import threading
import unittest
from urllib.request import Request, urlopen


class ClientAddress(unittest.TestCase):
    def test_ingress_appends_observed_peer_after_untrusted_entries(self):
        nginx = shutil.which('nginx')
        self.assertIsNotNone(nginx, 'Install nginx and put it on PATH to test the ingress template.')
        template = (Path(__file__).resolve().parents[1] / 'var/init/etc/nginx.conf').read_text()
        directive = '\n'.join(re.findall(r'proxy_set_header\s+[^;]+;', template))

        class Upstream(BaseHTTPRequestHandler):
            def do_GET(self):
                body = json.dumps({name: self.headers.get(name, '') for name in
                    ('X-Real-IP', 'X-Forwarded-Proto', 'X-Forwarded-Host')}).encode()
                self.send_response(200)
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *_):
                pass

        with HTTPServer(('127.0.0.1', 0), Upstream) as upstream:
            worker = threading.Thread(target=upstream.serve_forever)
            worker.start()
            try:
                with tempfile.TemporaryDirectory(prefix='wing-ingress-') as directory:
                    with socket.socket() as port:
                        port.bind(('127.0.0.1', 0))
                        address = port.getsockname()[1]
                    config = Path(directory) / 'nginx.conf'
                    config.write_text(
                        f'error_log stderr notice; pid {directory}/nginx.pid;\n'
                        'events {}\nhttp { access_log off; server {\n'
                        f'listen 127.0.0.1:{address};\n{directive}\n'
                        f'location / {{ proxy_pass http://127.0.0.1:{upstream.server_port}; }}\n'
                        '} }\n')
                    process = subprocess.Popen([nginx, '-p', directory, '-c', str(config),
                                                '-g', 'daemon off;'], stderr=subprocess.PIPE,
                                               text=True)
                    ready = threading.Event()
                    messages = []

                    def drain():
                        for line in process.stderr:
                            messages.append(line)
                            if 'start worker processes' in line:
                                ready.set()
                        ready.set()

                    reader = threading.Thread(target=drain)
                    reader.start()
                    try:
                        self.assertTrue(ready.wait(30), 'nginx did not become ready')
                        self.assertIsNone(process.poll(), ''.join(messages))
                        for supplied, expected in [
                            ('10.0.0.1, 198.51.100.7', '10.0.0.1, 198.51.100.7, 127.0.0.1'),
                            (None, '127.0.0.1'),
                        ]:
                            request = Request(f'http://127.0.0.1:{address}/')
                            if supplied is not None:
                                request.add_header('X-Forwarded-For', supplied)
                                request.add_header('X-Forwarded-Proto', 'https')
                                request.add_header('X-Forwarded-Host', 'evil.example')
                            with urlopen(request, timeout=30) as response:
                                headers = json.loads(response.read())
                                self.assertEqual(headers['X-Real-IP'], expected)
                                self.assertEqual(headers['X-Forwarded-Proto'], 'http')
                                self.assertEqual(headers['X-Forwarded-Host'], f'127.0.0.1:{address}')
                    finally:
                        process.terminate()
                        try:
                            process.wait(timeout=30)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()
                        reader.join()
                        process.stderr.close()
            finally:
                upstream.shutdown()
                worker.join()


if __name__ == '__main__':
    unittest.main()

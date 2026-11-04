"""Exercise the shipped date/time component in Chromium, without application services."""
from pathlib import Path
import os
import subprocess
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
ASSETS = {
    'bootstrap.css': 'bootstrap@4.5.2/dist/css/bootstrap.min.css',
    'bootstrap-vue.css': 'bootstrap-vue@2.16.0/dist/bootstrap-vue.min.css',
    'vue.js': 'vue@2.6.7/dist/vue.min.js',
    'bootstrap-vue.js': 'bootstrap-vue@2.16.0/dist/bootstrap-vue.min.js',
    'lodash.js': 'lodash@4.17.5/lodash.min.js',
    'qs.js': 'qs@6.5.2/dist/qs.js',
    'axios.js': 'axios@0.18.0/dist/axios.min.js',
    'luxon.js': 'luxon@1.25.0/build/global/luxon.min.js',
}

with tempfile.TemporaryDirectory(prefix='wing-browser-') as directory:
    for name, package in ASSETS.items():
        with urllib.request.urlopen('https://cdn.jsdelivr.net/npm/' + package, timeout=60) as response:
            (Path(directory) / name).write_bytes(response.read())
    subprocess.run(['node', str(ROOT / 'author.t/browser/luxon-date-time.cjs'), directory],
                   cwd=ROOT, env=os.environ, check=True)

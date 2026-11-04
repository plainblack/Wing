import os
import importlib.util
from pathlib import Path
import select
import signal
import subprocess
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class IsolationTest(unittest.TestCase):
    def test_failed_test_does_not_hide_later_tests_in_the_selection(self):
        spec = importlib.util.spec_from_file_location('agent_tests', ROOT / 'bin/agent-tests.py')
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        seen = []

        def execute(test):
            seen.append(test.name)
            if test.name == 'status.t':
                raise RuntimeError('status.t failed')

        with patch.object(sys, 'argv', ['agent-tests.py', 'author.t/status.t', 'author.t/user.t']):
            with patch.object(runner, 'isolated_test', execute):
                with self.assertRaises(RuntimeError):
                    runner.main()
        self.assertEqual(seen, ['status.t', 'user.t'])

    def test_service_cleans_descendants_after_parent_exits(self):
        spec = importlib.util.spec_from_file_location('agent_tests', ROOT / 'bin/agent-tests.py')
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        child = 'import signal; signal.signal(signal.SIGTERM, lambda *_: exit()); print("ready", flush=True); signal.pause()'
        parent = f'import subprocess, sys; subprocess.Popen([sys.executable, "-c", {child!r}])'
        process = None
        try:
            with runner.service([sys.executable, '-c', parent], stdout=subprocess.PIPE) as process:
                self.assertEqual(process.stdout.readline(), b'ready\n')
                process.wait(timeout=10)
            readable, _, _ = select.select([process.stdout], [], [], 10)
            self.assertTrue(readable, 'Service left its descendant running after the parent exited')
            self.assertEqual(process.stdout.read(), b'')
        finally:
            if process:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.stdout.close()

    def test_database_test_ignores_ambient_application_configuration(self):
        result = subprocess.run(
            [sys.executable, 'bin/agent-tests.py', 'author.t/user.t'], cwd=ROOT,
            env={**os.environ, 'WING_CONFIG': '/does-not-exist/never-read-app-config'},
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('Tests=9', result.stdout)


if __name__ == '__main__':
    unittest.main()

import os
import importlib.util
from pathlib import Path
import select
import signal
import socket
import subprocess
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class IsolationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location('agent_tests', ROOT / 'bin/agent-tests.py')
        cls.runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.runner)

    def test_preserves_installed_perl_dependency_paths(self):
        with patch.dict(os.environ, {'PERL5LIB': str(ROOT / 'lib'), 'PERL5OPT': '-Mstrict'}):
            environment = self.runner.test_environment()
        self.assertEqual(environment.get('PERL5LIB'), str(ROOT / 'lib'))
        self.assertNotIn('PERL5OPT', environment)

    def test_mysql_logs_keep_draining_after_readiness(self):
        code = 'print("ready for connections", flush=True); print("x" * 1048576, flush=True)'
        with self.runner.service([sys.executable, '-c', code], stdout=subprocess.PIPE, text=True) as process:
            self.runner.wait_database(process)
            process.wait(timeout=10)

    def test_rejects_a_broker_owned_by_another_process(self):
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            port = listener.getsockname()[1]
        with self.runner.service([self.runner.binary('beanstalkd'), '-l', '127.0.0.1', '-p', str(port)]) as broker:
            self.runner.wait_queue(broker, port)
            with patch.object(broker, 'pid', os.getpid()):
                with self.assertRaisesRegex(RuntimeError, 'private'):
                    self.runner.wait_queue(broker, port)

    def test_invalid_slice_arguments_are_actionable(self):
        for args in (['--slice', '3'], ['--slice', 'a/8'], ['--slice', '1/8', 'author.t/user.t']):
            result = subprocess.run([sys.executable, '-B', 'bin/agent-tests.py', *args], cwd=ROOT,
                                    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            self.assertEqual(result.returncode, 2, result.stdout)
            self.assertNotIn('Traceback', result.stdout)

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
        child = 'import signal; signal.signal(signal.SIGTERM, signal.SIG_IGN); print("ready", flush=True); signal.pause()'
        parent = f'import subprocess, sys; subprocess.Popen([sys.executable, "-c", {child!r}])'
        output = None
        try:
            with runner.service([sys.executable, '-c', parent], stdout=subprocess.PIPE) as process:
                self.assertEqual(process.stdout.readline(), b'ready\n')
                output = os.fdopen(os.dup(process.stdout.fileno()), 'rb')
                process.wait(timeout=10)
            readable, _, _ = select.select([output], [], [], 10)
            if not readable:
                os.killpg(process.pid, signal.SIGKILL)
            self.assertTrue(readable, 'Service left its descendant running after the parent exited')
            self.assertEqual(output.read(), b'')
        finally:
            if output:
                output.close()

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

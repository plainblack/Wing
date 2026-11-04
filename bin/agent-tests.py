"""Run Wing author tests with disposable services, never application configuration."""
import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]


def run(args, **kwargs):
    subprocess.run(args, check=True, **kwargs)


@contextmanager
def service(args, **kwargs):
    process = subprocess.Popen(args, start_new_session=True, **kwargs)
    try:
        yield process
    finally:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            pass
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        if hasattr(process, 'log_reader'):
            process.log_reader.join()
        for stream in (process.stdout, process.stderr):
            if stream:
                stream.close()


def binary(name):
    path = shutil.which(name)
    if not path:
        raise RuntimeError(f'Install {name} and put it on PATH before running Wing checks.')
    return path


def test_environment():
    return {key: value for key, value in os.environ.items()
            if not key.startswith(('WING_', 'TGC_JOBBER_')) and key not in ('PERL5OPT', 'PERL5DB')}


def wait_database(database):
    event = threading.Event()
    ready = []

    def drain():
        for line in database.stdout:
            if 'ready for connections' in line:
                ready.append(True)
                event.set()
        event.set()

    database.log_reader = threading.Thread(target=drain, daemon=True)
    database.log_reader.start()
    if not event.wait(timeout=60) or not ready:
        raise RuntimeError('Disposable MySQL did not become ready. Check the installed MySQL version.')


def wait_queue(queue, port):
    deadline = time.monotonic() + 30
    while True:
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=1):
                break
        except OSError:
            if queue.poll() is not None or time.monotonic() >= deadline:
                raise RuntimeError('Disposable Beanstalkd did not become ready.')
    result = subprocess.run(
        ['perl', '-MBeanstalk::Client', '-e',
         'my $s = Beanstalk::Client->new({server => $ARGV[0]})->stats; '
         'die "Broker is not the private process\\n" unless $s->{pid} == $ARGV[1];',
         f'127.0.0.1:{port}', str(queue.pid)],
        env=test_environment(), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=30,
    )
    if result.returncode:
        raise RuntimeError('Refusing tests: broker is not the private process. '+result.stdout.strip())


def isolated_test(test):
    mysqld, mysql, broker = [binary(name) for name in ('mysqld', 'mysql', 'beanstalkd')]
    with tempfile.TemporaryDirectory(prefix='wing-check-', dir='/tmp') as directory:
        scratch = Path(directory)
        sock = str(scratch / 'mysql.sock')
        datadir = str(scratch / 'db')
        run([mysqld, '--no-defaults', '--initialize-insecure', '--datadir='+datadir,
             '--log-error='+str(scratch / 'initialize.log')], stdout=subprocess.DEVNULL)
        with service([mysqld, '--no-defaults', '--datadir='+datadir, '--socket='+sock,
                      '--pid-file='+str(scratch / 'mysql.pid'), '--skip-networking',
                      '--mysqlx=OFF', '--console'], stdout=subprocess.PIPE,
                     stderr=subprocess.STDOUT, text=True) as database:
            wait_database(database)
            client = [mysql, '--no-defaults', '--socket='+sock, '--user=root', '-N', '-B']
            identity = subprocess.check_output(client + ['-e', 'SELECT @@datadir,@@socket,@@skip_networking'], text=True).strip().split('\t')
            if len(identity) != 3 or Path(identity[0]).resolve() != Path(datadir).resolve() or identity[1:] != [sock, '1']:
                raise RuntimeError('Refusing tests: MySQL is not the private, networking-disabled instance.')
            run(client + ['-e', 'CREATE DATABASE wing_check'])
            with socket.socket() as listener:
                listener.bind(('127.0.0.1', 0))
                port = listener.getsockname()[1]
            with service([broker, '-l', '127.0.0.1', '-p', str(port)],
                         stdout=subprocess.DEVNULL, stderr=subprocess.PIPE) as queue:
                wait_queue(queue, port)
                (scratch / 'log.conf').write_text(
                    'log4perl.logger = ERROR, screen\n'
                    'log4perl.appender.screen = Log::Log4perl::Appender::Screen\n'
                    'log4perl.appender.screen.layout = SimpleLayout\n')
                config = {
                    'app_namespace': 'TestWing', 'api_key_permissions': ['view_my_account', 'edit_my_account'],
                    'db': ['DBI:mysql:database=wing_check;mysql_socket='+sock, 'root', '',
                           {'mysql_enable_utf8': 1}, {'quote_names': 1}],
                    'cache': {'driver': 'FastMmap', 'root_dir': str(scratch / 'cache'),
                              'cache_size': '1M', 'serializer': 'JSON'},
                    'log4perl_config': str(scratch / 'log.conf'),
                    'mkits': str(ROOT / 'author.t/var/mkits'), 'rpc_limit': 30, 'sitename': 'localhost',
                    'tenants': {'namespace': 'Acquisitions', 'app_dir': str(ROOT / 'author.t/tenant_files'),
                                'domain': 'localdomain', 'db_driver': {'prefix': 'DBI:mysql:database=',
                                                                     'suffix': ';mysql_socket='+sock}},
                    'wingman': {'pid_file_path': str(scratch / 'wingman.pid'), 'max_workers': 2,
                                'beanstalkd': {'server': f'127.0.0.1:{port}', 'default_tube': 'wingman_test', 'ttr': 60},
                                'plugins': {'TestWing::Wingman::HelloWorld': {'phase': 'howdy'},
                                            'TestWing::Wingman::EchoJson': {'phase': 'EchoJson'}}},
                }
                (scratch / 'config.json').write_text(json.dumps(config))
                environment = test_environment()
                environment.update(WING_HOME=str(ROOT), WING_APP=str(ROOT / 'author.t'),
                                   WING_OWNER=str(ROOT / 'author.t'), WING_CONFIG=str(scratch / 'config.json'),
                                   TGC_JOBBER_BEANSTALKD_BINARY=broker)
                includes = ['-I'+str(ROOT / path) for path in ('lib', 'author.t/lib', 'author.t', 'author.t/tenant_files/lib')]
                run(['perl', *includes, '-MWing', '-MDBIx::Class::DeploymentHandler', '-e',
                     'my $db = Wing->db; $db->deploy; '
                     'my $dh = DBIx::Class::DeploymentHandler->new({schema => $db, '
                     'script_directory => "$ENV{WING_APP}/dbicdh"}); '
                     '$dh->install_version_storage; $dh->add_database_version({version => $db->schema_version});'],
                    env=environment)
                with service(['prove', *includes, str(test)], cwd=ROOT / 'author.t', env=environment) as tests:
                    if tests.wait() != 0:
                        raise RuntimeError(f'{test.relative_to(ROOT)} failed in isolated services.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--slice', help='Run the next full-suite slice, k/count')
    parser.add_argument('tests', nargs='*')
    args = parser.parse_args()
    available = sorted([*ROOT.glob('author.t/*.t'), *ROOT.glob('author.t/*_test.py')])
    if args.slice:
        if args.tests:
            parser.error('Choose either --slice or named tests, not both.')
        try:
            index, count = map(int, args.slice.split('/'))
        except ValueError:
            parser.error('Slice must be k/count with 1 <= k <= count.')
        if not 1 <= index <= count:
            parser.error('Slice must be k/count with 1 <= k <= count.')
        tests = available[index-1::count]
    else:
        tests = [(ROOT / name).resolve() for name in args.tests]
        if not tests:
            parser.error('Name at least one author test, or supply --slice k/count.')
        if any(test not in available for test in tests):
            parser.error('Only checked-in author.t/*.t and author.t/*_test.py tests may run.')
    failures = []
    for test in tests:
        try:
            if test.suffix == '.py':
                run([sys.executable, '-B', str(test)], cwd=ROOT)
            else:
                isolated_test(test)
        except (RuntimeError, subprocess.SubprocessError, OSError) as error:
            failures.append(f'{test.relative_to(ROOT)}: {error}')
    if failures:
        raise RuntimeError('\n'.join(failures))


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, lambda *_: sys.exit('Wing checks terminated; cleaning disposable services.'))
    try:
        main()
    except (RuntimeError, subprocess.SubprocessError, OSError) as error:
        sys.exit(str(error))

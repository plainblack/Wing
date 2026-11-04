# Agent checks

The policy targets `master`. Code changes must change an author test; verification
runs the changed tests, and each merge runs one of eight slices of the complete
`author.t/*.t` and `author.t/*_test.py` suite. Failures do not skip later tests in
the slice. The policy tool records slice failures as issues.

Run a selected test with:

```
python3 -B bin/agent-tests.py author.t/user.t
```

Prerequisites are Python 3, Wing's installed Perl dependencies, and `mysqld`,
`mysql`, and `beanstalkd` on PATH. The isolation tests additionally use Python's
standard library. No new package is required by the runner.

Each Perl test gets a newly initialized MySQL datadir with networking disabled,
a private Unix socket, a separate FastMmap cache directory, and a new loopback
Beanstalkd process. The runner verifies MySQL's datadir, socket and networking
setting before creating the test database. It uses the current TestWing schema's
supported DBIx::Class `deploy` method. It does not apply the historical version-5
migration or alter SQL modes, generated SQL, or installed dependencies.

Application WING configuration and Perl injection variables are excluded from
the test environment. Configuration and logs live in the temporary directory.
The runner terminates its service process groups and removes the temporary data
on completion or termination. Never run legacy author tests directly against an
application configuration: some deploy tables or delete users.

## Bootstrap blocker

Ticket #56 tracks initial setup. The REST tests `status.t`, `tenantsso.t` and
`wingman_rest.t` require `Test::Wing::Client`, which is absent from this checkout
and the installed Perl libraries. The installed Wing::Client 1.1000 and the
plainblack/Wing-Client upstream tree do not supply it. Restore the genuine helper
from its authoritative source, with its dependencies, before claiming those
tests have run. Do not skip them or substitute a mock client to land this setup.

The historical TestWing version-5 install SQL also fails on MySQL 8.4.7 because
the `api_key.user_id` and `users.id` foreign-key columns have incompatible
collations. Current TestWing schema deployment and the nine `user.t` assertions
pass on the same isolated server with default strict SQL mode.

No production deployment procedure is documented for Wing.

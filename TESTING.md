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
setting before creating the test database, and checks the broker's reported PID
against the process it started. It uses the current TestWing schema's
supported DBIx::Class `deploy` method, then DeploymentHandler's
`install_version_storage` and `add_database_version` methods. It does not apply
the historical version-5 application migration or alter SQL modes, generated
SQL, or installed dependencies.

Application WING configuration and Perl injection variables are excluded from
the Perl test environment; installed Perl library paths are preserved. Configuration
and cache data live in the temporary directory. MySQL output is continuously drained.
The runner terminates its service process groups and removes the temporary data
on completion or termination. Never run legacy author tests directly against an
application configuration: some deploy tables or delete users.

## Existing test prerequisites

Ticket #56 tracks initial setup; #57 tracks these pre-existing failures. The REST
tests `status.t`, `tenantsso.t` and
`wingman_rest.t` require `Test::Wing::Client`, which is absent from this checkout
and the installed Perl libraries. The installed Wing::Client 1.1000 and the
plainblack/Wing-Client upstream tree do not supply it. Restore the genuine helper
from its authoritative source, with its dependencies, before claiming those
tests have run. Do not skip them or substitute a mock client to land this setup.

The historical TestWing version-5 install SQL also fails on MySQL 8.4.7 because
the `api_key.user_id` and `users.id` foreign-key columns have incompatible
collations. Current TestWing schema deployment and the nine `user.t` assertions
pass on the same isolated server with default strict SQL mode. The existing
15-assertion `loaddb.t` test also passes after version-storage initialization.

No production deployment procedure is documented for Wing.

## Date/time browser regression

`author.t/luxon_date_time_test.py` mounts the actual `public/wing.vue.js` component
in installed Playwright Chromium using the generated UI's pinned Vue 2.6.7,
Bootstrap 4.5.2, Bootstrap-Vue 2.16.0 and Luxon 1.25.0 assets. It requires network
access to download those assets from jsDelivr, Node, and an existing Playwright
runtime with its Chromium browser installed. If Playwright is outside Node's
module search path, set `NODE_PATH` to the installed runtime's `node_modules`
directory. No application server, database, cache or broker is used.

```
python3 -B bin/agent-tests.py author.t/luxon_date_time_test.py
```

The test checks rendered label geometry at 390px and 1440px in both browser
appearances, manual and picker modes, and both `wrap` settings. It also edits
real date/time controls and checks UTC values and both public events, including
immediate manual typing. It also checks joined borders and a 240px parent. Bootstrap
4 has no automatic dark theme, so the two appearance settings use the same CSS.
Set `WING_UI_ARTIFACTS` to an absolute directory to retain screenshots outside
the source tree. The existing policy includes this Python author test in
related verification and merge slices.

## Email acknowledgement recovery

`author.t/wingman_email_ack.t` uses the runner's native isolated broker and
MySQL, actual email plugins and `Wingman::Job`, and controlled SMTP/child
publication boundaries. It covers true, false, throwing and lost-response
deletion, partial delivery, failed burial, invalid/missing tube exclusions,
worker disconnection, and actual autokick retention. It sends no outbound mail.

Before running the email plugins, configure their actual tube names in
`wingman/autokick_excluded_tubes` on every worker and autokick host. They now
confirm burial before irreversible delivery and require manual reconciliation
after failure or a worker crash. See `Wingman::Role::EmailRecovery` for recovery
instructions and the limits of this policy.

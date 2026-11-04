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

## Client address propagation

`author.t/client_ip.t` and `author.t/web_client_ip.t` exercise real Dancer
requests, an IP-gated description with a real result set, expanded parameters,
and login/SSO persistence in the runner's disposable database and cache.
`author.t/nginx_client_ip_test.py` additionally requires nginx on PATH and uses
an owned loopback nginx process and HTTP upstream to check the generated
template's header directive against spoofed forwarding entries and no header.
It stops both services before returning.

The generated template appends nginx's observed peer. Behind a load balancer
this is the balancer address. Existing deployments must configure their trusted
ingress chain explicitly if they need the client beyond it; never copy an
unrestricted client-supplied forwarding header into X-Real-IP.

## Web session request security

`author.t/web_session_security.t` and `author.t/rest_session_cookie.t` send real
HTTP requests through Wing's Dancer PSGI app using the runner's isolated MySQL
and cache. They cover origin refusals before SQL or password-reset cache lookup,
successful login/create/reset/SSO, admin impersonation, and all Wing session
cookie writers on HTTP, native HTTPS and forwarded HTTPS.

Session cookies retain their five-year expiry, root or `/api` path, and
JavaScript access, and now use `SameSite=Lax`. `Secure` follows Dancer 1.3522's
`request->secure`. Forwarded protocol and host are trusted only when Dancer's
`behind_proxy` is enabled. Enable it only behind an ingress that overwrites
forwarded headers and prevents direct application access. No proxy setting is
enabled by this change.

`Wing::RequestSecurity::same_origin_error(request)` is the shared validation
seam for REST callers. It returns undef or an actionable error string, without
accessing sessions, SQL or cache. Callers must send their own 403 response before
lookup or mutation and outside authentication eval blocks. This change protects
web POST `/login`, `/account/create`, `/account/reset-password-code`, and the
session-renewing `/account`; REST mutation enforcement is ticket #55. External
Facebook GET callbacks retain their existing flow.

The implementation was checked against installed Dancer 1.3522 Cookie, Request
and Config POD and Cookie/Request source, installed URI POD, and RFC 6454
(https://www.rfc-editor.org/rfc/rfc6454), including scheme and effective port
comparison, null origins and strict serialized-origin syntax.

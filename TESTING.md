# Agent checks

The policy targets `master`. Code changes must change an author test; verification
runs the changed tests, and each merge runs one of eight slices of the complete
`author.t/*.t` suite. Failures do not skip later tests in the slice. The policy
tool records slice failures as issues.

Run selected tests, or a slice, with:

```
perl author.t/run.pl author.t/user.t
perl author.t/run.pl --slice 1/8
```

The runner and tests need only Perl, Wing's Perl dependencies and the author-test
modules in `bin/setup/03_install_perl_modules.sh`. They use the running dev MySQL
and Beanstalkd named in `author.t/etc/test.conf`; nothing starts its own `mysqld`,
`beanstalkd`, nginx or browser, and nothing downloads files. If a service is down,
the tests fail; start it and rerun.

Create the test database and account once, as the MySQL root user, with
`author.t/bin/createdb.sql`. The `testwing` account can reach only `testwing` and
databases named `testwing_*`. The runner deploys the TestWing schema into
`testwing` once per run. Before each test file it empties every table, drops
`testwing_*` databases, deletes jobs in the `wingman_test` tube and tubes named
`wingman_test.*`, starts a fresh FastMmap cache directory and rewrites the test
configuration. When the run ends, even after a failure or interrupt, it drops the
schema and `testwing_*` databases and clears those tubes again. Other tubes on the
dev broker belong to other applications; tests that use the broker create only
`wingman_test` tubes, plus `jobber.wingman_test` for Jobber ownership checks and
tube `0` for the zero-named tube check, and delete their own jobs.

Application WING configuration and Perl injection variables are excluded from the
test environment; installed Perl library paths are preserved.

## Generated TestWing installs

Ticket #57 is covered by `author.t/master_install.t`, which runs the actual
`wing db --install --force` command in an additional `testwing_install_check`
database. It verifies version storage, that the install keeps the server SQL mode, matching user/API-key collations and actual foreign-key rejection.

The tenant SSO client test provisions a real Acquisitions tenant through
`Wing::Role::Result::Site::create_database`. Its version-2 fixture was generated
from the current tenant model using DeploymentHandler's `prepare_install`,
`prepare_upgrade` (1 to 2) and `prepare_downgrade` (2 to 1), matching `wing db --prep`.
The version-1 fixture is preserved. This does not apply a migration to any
application database. The test checks the login redirect itself, before the
account page's separate secondary-verification flow.

TestWing master schema version 6 was generated from the current model using
DeploymentHandler's documented `prepare_install`, `prepare_upgrade` (5 to 6)
and `prepare_downgrade` (6 to 5), with the same arguments as `wing db --prep`.
Versions 1 through 5 remain unchanged. The version-5 users table lacks the
explicit UTF-8 table collation present on its foreign-key references, so that
historical install fails against MySQL 8.4's native database defaults. Version 6
supplies consistent metadata and includes the current User fields and indexes.
MySQL requires matching collations on character foreign-key columns:
https://dev.mysql.com/doc/refman/8.4/en/create-table-foreign-keys.html.

The regression also installs the unchanged version 5 into a separate database
with the historical UTF-8 default, then exercises the generated upgrade,
downgrade and repeat upgrade, retaining existing company data. This compatibility
fixture does not change server settings, disable constraints or rewrite SQL.
The generated downgrade removes the five User columns added in version 6 and
therefore discards their data. It runs only on the `testwing_legacy_check` fixture. No
application database or TGC migration is applied.

No production deployment procedure is documented for Wing.

## Autokick

`wing autokick_jobs` kicks fresh buried jobs again. A job kicked more than once,
older than twelve hours or with an unreadable payload stays buried, alerts
`wing_admin`, and is moved behind the other buried jobs in its tube with
beanstalkd 1.12+'s `reserve-job` and `bury` (priority kept), so fresh jobs behind
it are still kicked (#60). Beanstalk::Client 1.07 has no `reserve_job`, so
`Wingman->reserve_job` sends the command through the client's private
`_interact`; https://github.com/gbarr/perl-beanstalk-client/issues/13 asks for a
public method. If the command dies between `reserve-job` and `bury`, the broker
returns that job to ready.

Tubes in `wingman/autokick_excluded_tubes`, and the email tube
(`wingman/email_tube`, or the default tube when that is unset), are never kicked
and keep the quieter alert rule: more than one buried job, or a stuck or old head.
A buried SendTemplatedEmail, EmailAllAdmins or EmailAllUsers job in any other tube
is neither kicked nor moved, because losing either a kick or a reservation could
send it again. It alerts when it is stuck or old, or when buried jobs wait behind
it. Installations without `email_tube` therefore get no kicks on their default tube.
A `retained` plugin outcome is kicked unless its tube is excluded.

`wingman_shared_broker.t` covers kicking, a stuck head with fresh jobs behind it,
a job that vanishes before its kick, email jobs in an ordinary tube, the email tube rule, malformed and uninstalled
payloads, excluded tubes, broker errors and Jobber isolation, on tubes it owns.
`wingman_job_outcomes.t` exercises the real job runner with a plugin's delayed
release beside a buried head. `wingman_monitor_cli.t` runs the actual CLI with a
temporary configuration and an in-memory SQLite bootstrap. The CLI sees every
tube on the shared dev broker, so the test excludes every tube that exists when
it starts and runs with `WING_NO_EMAIL` set.

## First-party account access

`author.t/web_account_permissions.t` exercises real Dancer HTTP requests against
the runner's test database and cache. Account pages check the same permissions as
their REST equivalents: viewing settings, API keys and SSO success needs
`view_my_account`; saving settings, managing API keys, deactivating and secondary
verification need `edit_my_account`. SSO sessions with those grants are allowed,
SSO sessions without them get 450, and an admin's SSO session needs the same grants
(`check_permissions` no longer passes every permission for admins). No SSO request,
allowed or refused, receives a site session cookie, and a user cannot approve another
user's authorization request. SSO consent
(`GET /sso`, `/sso/authorize`) and Facebook linking refuse every SSO session, so an
application cannot grant itself permissions or link a login provider. The test covers
cookie and parameter credentials, invalid-session reauthentication, Facebook linking
with the external OAuth boundary controlled, anonymous login entry, and site-session
key management and consent. `author.t/rest_mutation_auth.t` checks that an admin SSO
session without `edit_my_account` is refused on REST.

`author.t/web_admin_permissions.t` covers all shipped admin web routes with
admin SSO cookies/parameters, successful admin site sessions, ordinary users,
missing/invalid/expired sessions and refused password/impersonation effects.
`get_admin_by_session_id` refuses SSO sessions, because no API key permission grants
admin rights. Trends and Wingman pages use this same helper.

`author.t/account_pages.t` renders the shipped account templates and follows the
REST endpoints their Vue objects call, served by `author.t/bin/rest-app.pl` because
Wing's web and REST routes cannot load in one process. It verifies populated
account fields, a saved edit after reload, and the owner's actual API keys and links.

Existing applications copy the account templates at generation time. They must
adopt `account.json` for settings properties and `apikeys_uri` for the key-list
endpoint when upgrading to this version. The current user remains a row object
for existing header/template methods. Wing does not replace consumers' copied
views. TGC adoption is tracked separately at
https://github.com/plainblack/TGC/issues/4284.


## Email acknowledgement recovery

`author.t/wingman_email_ack.t` uses the dev broker and the runner's test
database, actual email plugins and `Wingman::Job`, and controlled SMTP/child
publication boundaries. It covers true, false, throwing and lost-response
deletion, partial delivery, failed burial, delivery with neither
`wingman/email_tube` nor `wingman/autokick_excluded_tubes` configured,
worker disconnection, actual autokick retention of email, the immediate `stuck_wingman_job`
admin alert for every failure that leaves a job buried (and a failed alert), and a
bad address (Ouch 442) that SendTemplatedEmail logs and deletes. Two cases run the real
`Wing->send_templated_email` with `Email::Sender::Simple::send` throwing the
failure Email::Sender's SMTP transport raises for a refused RCPT: a 550 refusal becomes
442 and the job is deleted, a 450 refusal stays buried and alerts. It sends no outbound mail.

The email plugins confirm burial before irreversible delivery and require manual
reconciliation after failure or a worker crash. See `Wingman::Role::EmailRecovery` for recovery
instructions and the limits of this policy.

## Client address propagation

`author.t/client_ip.t` and `author.t/web_client_ip.t` exercise real Dancer
requests, an IP-gated description with a real result set, expanded parameters,
and login/SSO persistence in the runner's test database and cache.
`author.t/nginx_client_ip.t` checks that the generated template sends nginx's
resolved `$remote_addr` as a single X-Real-IP, sets the scheme and host headers
from nginx variables, and trusts no proxy by default. `client_ip` returns
X-Real-IP as one value, or the direct peer when it is empty.

The template uses nginx's realip module
(https://nginx.org/en/docs/http/ngx_http_realip_module.html), which source builds
need `--with-http_realip_module` for. Behind a load balancer, add one
`set_real_ip_from <CIDR>;` line per balancer range in the server block; nginx
then takes the last X-Forwarded-For address those ranges did not add. Requests
from any other peer keep that peer's address, so clients cannot choose it.

## Session cookies and cross-origin requests

`author.t/web_session_security.t`, `author.t/rest_session_cookie.t` and
`author.t/rest_request_security.t` send real HTTP requests through Wing's Dancer
PSGI app using the runner's test database and cache.

Session cookies keep their five-year expiry, root or `/api` path, and JavaScript
access, and use `SameSite=Lax`. `Secure` follows Dancer 1.3522's
`request->secure`, which trusts `X-Forwarded-Proto` only when `behind_proxy` is
enabled; enable it only behind an ingress that overwrites forwarded headers and
blocks direct application access. The generated nginx sets `X-Forwarded-Proto`
and `X-Forwarded-Host` from its own variables. The tests cover every Wing
session cookie writer on HTTP, native HTTPS and forwarded HTTPS.

Wing does not check `Origin` or `Sec-Fetch-Site`. Cross-origin web logins,
account creation, password resets, REST login and REST writes with a cookie or
an explicit `session_id` reach normal authentication. Applications that want an
origin check add their own.

## Dedicated email routing

`author.t/wingman_email_routing.t` uses the dev broker, real
`Wingman->put`, Wing helper, CLI, daemon worker loop, email plugins and admin
fan-out. Only daemon lifecycle and SMTP acceptance are controlled. It checks
legacy unset/null behavior, configured and explicit destinations, invalid
configuration before broker effects, shipped defaults, and actual autokick
retention of email alongside kicking of unrelated default-tube work. No
outbound email is sent. `wingman_email_ack.t` retains the acknowledgement,
reconciliation and disconnect regression matrix.

New installations set `wingman/email_tube` to `wingman.email`, which autokick
never kicks, and exclude no tubes; without it autokick would skip the default
tube. Default workers watch the email tube automatically; explicit watch lists
must include it. Follow the staged adoption steps in `Wingman::Role::EmailRecovery`
before changing an existing installation or removing its old exclusions. No
existing jobs are moved. The routing setting is optional for compatibility;
absent or null retains legacy default-tube routing.

The routing implementation uses installed Beanstalk::Client/Job 1.07 POD and
Beanstalkd 1.13's official protocol (tube syntax, `use`, `watch`, and burial):
https://github.com/beanstalkd/beanstalkd/blob/v1.13/doc/protocol.txt.

## Generated mutation authorization

`author.t/rest_mutation_auth.t` sends HTTP requests through the real Dancer
PSGI app with the runner's test database, FastMmap cache and real SSO sessions. It checks
missing, invalid and expired sessions, absent API permission, deactivated users
and rate limits across generated create/update/delete. Transparent observers
prove refusal precedes model construction, target lookup, verification, extra
processing and mutation. Authorized CRUD is verified through HTTP reads.
Present empty/undefined permissions require authentication; omitted permissions
retain optional lookup and the existing model authorization rules.

The implementation uses installed Dancer 1.3522 Plugin/Handler POD and source,
Plack::Test POD and CHI's documented `expire` operation. Expiry is explicit and
rate-limit buckets are seeded across all minutes, without timing assertions.

## Read authorization and description context

`author.t/rest_read_auth.t` exercises actual Dancer PSGI HTTP requests with the
runner's test database, FastMmap cache and real SSO sessions. It reproduces the
owning user's private email exposure with an API key missing `view_my_account`,
and covers generated singleton and relationship reads, lists, expansions,
missing/invalid/cache-expired sessions, authorized owner visibility, explicit
anonymous contexts and omitted-context lookup.

Generated singleton and relationship reads retain optional authentication. Failed
authentication or permission checks return public fields with an explicit anonymous
context; authorized owners retain private visibility. Rate limits and unexpected
infrastructure errors propagate instead of becoming public responses. Empty/undefined permissions
also retain anonymous public reads. Relationship `verify_user` continues to require
a user. Mutation generators with present permissions remain strict. The tests load
the actual built-in User routes in single-tenant mode and exercise anonymous and
denied SSO public profiles, the documented query-token SSO read and session user
relationship links. Dancer `describe`
and `format_list` respect explicit `current_user => undef` as anonymous; only an
omitted context triggers optional lookup. Expanded parents retain their existing
public description behavior. No session lifecycle or CRUD option forwarding is
changed; those are tracked separately.

Checked against installed Dancer 1.3522 Plugin/Handler POD and Plack::Test 1.0054
POD. The HTTP tests exercise the actual serializers and result roles without
mocking authentication, database, cache or field visibility.

## Combined CRUD options

`author.t/rest_crud_options.t` sends HTTP requests through the actual Dancer
PSGI app with the runner's test database and cache. It checks aliased
metadata and persisted CRUD, mutation callbacks, denied SSO permission errors,
undefined callbacks, permission-aware metadata context and rate limits,
and the built-in APIKey caller including view-only owner reads. The mutation and read authorization matrices
also exercise `generate_crud`, covering present empty/undefined permissions,
optional omission, public-only denied reads and authorized private visibility.

## Admin job email routing

`author.t/admin_email_routing.t` renders the shipped admin tube page through the
actual web route with a real admin session and reads the email phases it gives the
page. It submits jobs to the actual REST PSGI app the way the page's Add Job does,
dropping the tube for those phases, and inspects native broker job statistics and
the tube's job list. No worker runs and no outbound mail is sent.

## Ended session authentication

`author.t/rest_ended_session.t` sends generated mutations through the actual
Dancer PSGI app with the runner's test database and cache. Sessions past their
absolute expiry, after a password change, or with a revoked floor badge return
the existing 401 login error before model verification or mutation, and their
cache entries are removed. Active sessions are still renewed. `Wing::Session::end`
clears the in-memory user, so no caller can use an ended session for the rest of
the request. `author.t/web_ended_session.t` checks that Wing::Web's `get_session`
also returns no session once it has ended. Both tests also pass session objects to
`get_user_by_session_id`. A passed session object is reloaded by its id and gets the
same checks, so one ended in this or another instance, after a password change or
for a deactivated user, or a User object, returns 401, and a missing permission 450.

## Missing session user

`author.t/rest_missing_user.t` deletes the user behind a cached site or SSO
session, with and without the `user-changed-<id>` marker, and sends a generated
mutation through the actual Dancer PSGI app with the runner's test database and
cache. Each returns the 401 login error instead of a 500 and removes the session's
cache entry. `extend` and SSO `check_permissions` end a session whose user no
longer resolves, so Wing::Web's `get_session` returns no session either.

## Account route permissions

`author.t/rest_route_permissions.t` sends real HTTP requests through the actual
built-in User and APIKey routes with the runner's test database and cache. The
User relationship routes (`apikeys`, `apikeypermissions`) and `GET /api/apikey/:id`
declare `view_my_account`, with the generated-read rule: anonymous clients and SSO
sessions without the permission get public fields only. `GET /api/user/whoami` and
`GET /api/user` and `GET /api/user-not-me` still require a session (441 without one) and still identify an SSO
user lacking the permission, but describe results publicly for that session.
Authorized SSO owners and ordinary site sessions keep private fields.
`GET /api/user/:id/firebase-jwt` issues a write-capable Firebase credential, so it
requires `edit_my_account`: SSO sessions without it get 450 and no token, even with
`view_my_account`. Anonymous clients get 441; authorized SSO owners and site sessions
receive the signed JWT, which the test checks against a key it generates.
`author.t/web_chat_permissions.t` checks the same rule for the web `GET /chat` page,
which renders the same credential: Wing::Web's `get_user_by_session_id` and `get_session`
now accept `permissions` like Wing::Rest's, so SSO sessions without `edit_my_account` get
450 (cookie or `session_id` parameter), anonymous visitors 401, and authorized SSO and
site sessions the page with a JWT signed by a test key held only in memory.
The `query` search on `GET /api/user` and `GET /api/user-not-me` matches username and
real name for everyone, and email only for admins, so other sessions cannot find which
account owns an email or probe email prefixes. Applications that grant other users
private-field visibility by extending `can_edit` do not get email search from it.

## Session user cache

`author.t/session_user_cache.t` sends real requests through the Dancer PSGI app
with the runner's test database and cache, and counts `users` queries through
DBIx::Class's debug callback. Sessions read their user from the per-user cache
entry `user-data-<id>`. User `update` and `delete` remove that entry and set
`user-changed-<id>` for five minutes; while any truthy marker is set, sessions
read the user from the database and cache nothing. Otherwise a session fills the
cache with a shared-lock read, which waits for an open transaction that changed
the user, so an uncommitted or rolled back change is never cached even after the
marker expires. The test removes the marker to stand in for its expiry, because
logins update the user too, and lowers its lock wait so the blocked read ends. User changes made
outside DBIx::Class row `update` or `delete` (resultset `update`, raw SQL,
another application) must remove `user-data-<id>`, or set `user-changed-<id>` for
at least seven days, the entry's lifetime, and not remove it.

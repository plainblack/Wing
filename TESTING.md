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
`install_version_storage` and `add_database_version` methods. This bootstrap does
not apply the historical version-5 install or alter SQL modes, generated SQL,
or installed dependencies.

Application WING configuration and Perl injection variables are excluded from
the Perl test environment; installed Perl library paths are preserved. Configuration
and cache data live in the temporary directory. MySQL output is continuously drained.
The runner terminates its service process groups and removes the temporary data
on completion or termination. Never run legacy author tests directly against an
application configuration: some deploy tables or delete users.

## Author-only client prerequisites

The REST tests `status.t`, `tenantsso.t` and `wingman_rest.t` use the genuine
[`Test::Wing::Client`](https://github.com/perlDreamer/Test-Wing-Client) helper.
It is a separate project, not part of Wing::Client. Its version 0.0300 source
has no CPAN release or generated installer, so use the pinned, unmodified
checkout on Perl's library path. Do not copy it into Wing or replace it with
a mock client. These dependencies are for author tests, not deployed apps.

With Wing's ordinary Perl dependencies installed, install the additional client
dependencies and the pinned browser test wrapper with their upstream tests enabled:

```
cpanm HTTP::Thin HTTP::CookieJar::LWP HTTP::Message::PSGI 'Test::WWW::Mechanize::Dancer@0.0100'
git clone https://github.com/perlDreamer/Test-Wing-Client.git "$HOME/.cache/wing-author/Test-Wing-Client"
git -C "$HOME/.cache/wing-author/Test-Wing-Client" checkout --detach 8f3fab07200a57df790228bd1ff16d8d2f046ccf
export PERL5LIB="$HOME/.cache/wing-author/Test-Wing-Client/lib${PERL5LIB:+:$PERL5LIB}"
(cd "$HOME/.cache/wing-author/Test-Wing-Client" && prove -Ilib -It/lib t/*.t)
python3 -B bin/agent-tests.py author.t/status.t author.t/tenantsso.t author.t/wingman_rest.t author.t/tenantsso_client.t
```

Clone once; on later runs verify `git -C ... rev-parse HEAD` matches that commit
and `git -C ... status --short` is empty before exporting `PERL5LIB`. The helper's
28 upstream assertions pass with installed Wing::Client 1.1000 and Dancer 1.3522.
The official Dancer-wrapper 0.0100 archive is
`https://cpan.metacpan.org/authors/id/W/WW/WWOLF/Test-WWW-Mechanize-Dancer-0.0100.tar.gz`
(SHA256 `2a3a00e0b45673df74b18bd140ca2db45eae29f7dda66f8f8c3475c17d64a8d7`).
Its dependencies include Test::WWW::Mechanize::PSGI and Test::WWW::Mechanize;
cpanm resolves these and runs their tests. Do not use `--notest` or force a
failed dependency installation.

The two Chromium tests also need the existing Playwright package visible to
Node. If it is installed outside this checkout, export `NODE_PATH` to the
absolute directory containing `playwright`, as described below, before invoking
the runner or `agent-policy`. The runner preserves `PERL5LIB` and `NODE_PATH`.

## Generated TestWing installs

Ticket #57 is covered by `author.t/master_install.t`, which runs the actual
`wing db --install --force` command in an additional disposable database. The
test refuses to create it unless the server matches the runner's private socket,
datadir and networking-disabled identity. It verifies version storage, native
strict mode, matching user/API-key collations and actual foreign-key rejection.

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
therefore discards their data. It runs only on this disposable fixture. No
application database or TGC migration is applied.

No production deployment procedure is documented for Wing.

## Plugin-owned retries and monitor-only recovery command

`wing autokick_jobs` retains its historical command name but now monitors only.
It reports buried counts and available head metadata without decoding jobs,
loading plugins or changing their states. Ordinary tubes with buried work request
inspection; excluded email/manual tubes retain the single-fresh-head quiet period,
old/stuck head thresholds and hidden-backlog alerts. Jobber remains outside Wing.

Plugins retry only identified temporary failures through a checked positive-delay
release of the same job. Their persistent reservation count supplies the attempt
budget, checked before effects; they own exhaustion, terminal acknowledgements
and operator reporting. PostWebHook retains its durable database failure counter
and existing rescheduling policy; it is not wrapped in another retry layer.
Existing plugin releases, legacy returns and explicit
failed/retained outcomes keep their contracts. Unknown exceptions do not become
automatic retries. No new outcome, configuration default or job envelope is added.
The former cron rule of two kicks within twelve hours is retired; twelve hours
remains an old-head monitoring threshold. Existing plugin-specific limits remain.
Inspection alerts repeat on each monitoring run until operators resolve the
buried work; there is no new deduplication or global retry policy.

Adopt this change in this order during an explicitly authorized release:

1. Stop automatic-kick cron execution on every recovery host before depending on
   terminal burial. Installing new workers alone does not stop old autokickers.
2. Deliver the monitor-only command to all recovery hosts. Review the relevant
   plugins' explicit release limits and acknowledgement/partial-progress behavior.
3. Restart relevant workers with the reviewed code, then resume monitoring cron.
   Existing `[phase,args]` messages and worker-owned acknowledgements are compatible;
   exceptions buried by an older worker now need manual inspection.
4. Inspect existing buried backlogs by known job ID and logged business IDs.
   Reconcile possible external effects and classify each failure before selective
   recovery. A previously fresh buried job behind a retained head is not migrated
   or automatically recovered. Existing job-ID kick/delete controls remain manual
   overrides; never bulk-kick an excluded/email tube.
5. A rollback must not restore an automatic-kick binary or cron while relying on
   terminal/manual burial. Keep monitoring stopped if that guarantee cannot hold.

No queue migration or live service operation is part of these repository checks.
This change does not provide exactly-once effects or a universal crash retry cap:
disconnects and TTR expiry can redeliver unacknowledged work, and limits remain at
their plugin owner. Persistent broker configuration controls durability. Existing
applications copy email templates and must update their copies through their own
release if they adopt revised alert instructions.

`wingman_shared_broker.t` checks read-only monitoring, native count/head behavior,
malformed/uninstalled plugins, manual/email policy and Jobber isolation.
`wingman_job_outcomes.t` exercises the real job runner with a plugin-owned delayed
release beside a buried head, same-ID persistence across worker disconnects and
preflight exhaustion after a lost reservation. The delay is advanced explicitly
for the next assertion; these tests do not sleep or depend on machine speed.
`wingman_monitor_cli.t` invokes the actual CLI with its own broker, temporary
configuration and in-memory SQLite bootstrap (using the installed DBD::SQLite).
It neither copies application configuration nor contacts an SMTP service.

## First-party account access

`author.t/web_account_permissions.t` exercises real Dancer HTTP requests against
the isolated database and cache. Account settings, API key management, secondary
verification and SSO consent require a site session. SSO sessions, including
admin sessions and sessions with `edit_my_account`, cannot use these pages to
mint site sessions or grant application permissions. The test covers cookie and
parameter credentials, invalid-session reauthentication, Facebook linking with
the external OAuth boundary controlled, anonymous login entry, and site-session key
management and consent. REST routes retain their existing permission scopes.

`author.t/web_admin_permissions.t` covers all shipped admin web routes with
admin SSO cookies/parameters, successful admin site sessions, ordinary users,
missing/invalid/expired sessions and refused password/impersonation effects.
`get_admin_by_session_id` always requires a site session, including when callers
pass other session options. Trends and Wingman pages use this same helper.

`author.t/account_pages.t` renders the shipped account templates and runs Chromium
against isolated loopback web and REST apps. It verifies populated account fields,
a saved edit after reload, and the owner's actual API keys and links. It requires
the existing Node/Playwright, Test::TCP and HTTP::Server::PSGI prerequisites described
below. Set `ACCOUNT_PAGE_ARTIFACTS` to retain 1440px and 390px screenshots in both
browser appearances; Bootstrap 4 uses the same CSS in both.

Existing applications copy the account templates at generation time. They must
adopt `account.json` for settings properties and `apikeys_uri` for the key-list
endpoint when upgrading to this version. The current user remains a row object
for existing header/template methods. Wing does not replace consumers' copied
views. TGC adoption is tracked separately at
https://github.com/plainblack/TGC/issues/4284.

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
enabled by this change. The shipped `var/init/config.yml` already enables
`behind_proxy`; its generated nginx now overwrites `X-Forwarded-Proto` with
nginx's observed scheme and `X-Forwarded-Host` with the request authority,
including its port. If TLS terminates at an earlier load balancer, explicitly
configure the trusted ingress chain to establish the external scheme and host;
nginx's own scheme is HTTP in that topology. Existing deployed configs are not
modified automatically.

`Wing::RequestSecurity::same_origin_error(request)` is the shared validation
seam for REST callers. It returns undef or an actionable error string, without
accessing sessions, SQL or cache. Callers must send their own 403 response before
lookup or mutation and outside authentication eval blocks. This change protects
web POST `/login`, `/account/create`, `/account/reset-password-code`, and the
session-renewing `/account`; REST mutation enforcement is described below. External
Facebook GET callbacks retain their existing flow.

The implementation was checked against installed Dancer 1.3522 Cookie, Request
and Config POD and Cookie/Request source, installed URI POD, and RFC 6454
(https://www.rfc-editor.org/rfc/rfc6454), including scheme and effective port
comparison, null origins and strict serialized-origin syntax.

## REST mutation request security

`author.t/rest_request_security.t` sends real HTTP requests through Dancer's
PSGI app, using the isolated runner's native database and cache. It exercises
actual generated User CRUD routes, custom routes and REST credential login.
SQL tracing and transparent cache observation assert zero lookups or mutations
on refusal, including login requests with no existing cookie. HTTP reads verify
successful generated creation, update and deletion.

Wing::Rest checks every unsafe method (all except GET, HEAD and OPTIONS) in its
before hook, outside generated authentication evals. Cross-site fetch metadata
and mismatched, null or malformed Origin receive the usual Wing JSON 403 error
with instructions to reload and submit from this site. Headerless API clients
continue to work. Explicit session_id parameters have no exemption, including
JSON null/false/containers, empty form values, and valid session IDs. This also
protects POST /api/session before credential lookup or a cookie write. No cookie
is required to trigger enforcement. By default, cross-origin browser integrations must submit from the API origin.
Installations can opt into `rest/allow_cookieless_cross_origin_writes` in Wing's
JSON configuration. Requests with any Cookie header remain refused; requests
without one reach normal authentication, including explicit session parameters.
Cross-origin credential login returns a usable token without `Set-Cookie`, even
for a form navigation. Custom routes must also avoid issuing ambient credential
cookies cross-origin. See `Wing::Rest` for configuration and the installation
trust requirements. This adds no CORS allowlist or authentication mode.
The scheme/host and trusted ingress requirements above apply unchanged.

The request boundary uses the installed Dancer 1.3522 Request, hook, Response
and halt POD/source and URI canonicalization POD. Dancer's before-hook exceptions
reach Wing's existing Ouch error handler, which preserves the error envelope
rather than wrapping a refusal as a result.

The same test also exercises the opt-in with real developer login, explicit
session authentication and logout. It checks null/malformed origins and fetch
metadata, session/cart/unknown/empty cookies, and zero SQL/cache/route activity
on cookie-backed refusals. HTTP response assertions prove cross-origin form
login cannot install a session cookie; existing cookie and web security tests
retain coverage of same-origin/headerless cookie writers and web login guards.

## Dedicated email routing

`author.t/wingman_email_routing.t` uses the native isolated broker, real
`Wingman->put`, Wing helper, CLI, daemon worker loop, email plugins and admin
fan-out. Only daemon lifecycle and SMTP acceptance are controlled. It checks
legacy unset/null behavior, configured and explicit destinations, invalid
configuration before broker effects, shipped defaults, and actual autokick
retention of email alongside recovery of unrelated default-tube work. No
outbound email is sent. `wingman_email_ack.t` retains the acknowledgement,
reconciliation and disconnect regression matrix.

New installations set `wingman/email_tube` to `wingman.email` and exclude only
that tube. Default workers watch it automatically; explicit watch lists must
include it. Follow the staged adoption steps in `Wingman::Role::EmailRecovery`
before changing an existing installation or removing its old exclusions. No
existing jobs are moved. The routing setting is optional for compatibility;
absent or null retains legacy default-tube routing.

The routing implementation uses installed Beanstalk::Client/Job 1.07 POD and
Beanstalkd 1.13's official protocol (tube syntax, `use`, `watch`, and burial):
https://github.com/beanstalkd/beanstalkd/blob/v1.13/doc/protocol.txt.

## Generated mutation authorization

`author.t/rest_mutation_auth.t` sends HTTP requests through the real Dancer
PSGI app with isolated MySQL, FastMmap cache and real SSO sessions. It checks
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
runner's isolated MySQL, FastMmap cache and real SSO sessions. It reproduces the
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
PSGI app with the runner's disposable database and cache. It checks aliased
metadata and persisted CRUD, mutation callbacks, denied SSO permission errors,
undefined callbacks, permission-aware metadata context and rate limits,
and the built-in APIKey caller including view-only owner reads. The mutation and read authorization matrices
also exercise `generate_crud`, covering present empty/undefined permissions,
optional omission, public-only denied reads and authorized private visibility.

## Admin job email routing

`author.t/admin_email_routing.t` requires installed Node and Playwright 1.62.1
with Chromium (set `NODE_PATH` to its installed `node_modules` directory when
needed), plus the Perl runner prerequisites, Test::TCP and HTTP::Server::PSGI.
It loads the shipped admin template through the actual web route with a real
admin session, clicks Add Job in Chromium, submits to the actual REST PSGI app,
and inspects native broker job statistics. Wing ships separate web and REST
apps; the browser transport routes `/api` to the isolated REST listener while
preserving the public Host. The pinned CDN assets in the shipped header require
network access. Missing prerequisites fail the test, rather than skipping it.
No worker runs and no outbound mail is sent. Policy related verification and
merge slices include this test. Run it with:

```
python3 -B bin/agent-tests.py author.t/admin_email_routing.t
```

Set `ADMIN_EMAIL_ARTIFACTS` to an absolute directory to retain desktop (1440px)
and phone (390px) screenshots in both browser color schemes. Bootstrap 4 has no
automatic dark theme, so the same CSS applies in both appearances.

The form omits the explicit destination for phases registered to
`Wingman::Plugin::EmailAllAdmins` and `Wingman::Plugin::SendTemplatedEmail`,
including configured aliases. Wing's existing routing selects `wingman/email_tube`;
absent or null retains the legacy default destination. Other phases retain the
viewed tube. The list displays a newly submitted job only when its actual broker
tube matches the viewed tube. Shared API and publication behavior still honors
explicit caller destinations.

Existing applications copy `var/init/views/admin/wingman_tube.tt` at generation
time. Upgrading Wing alone does not replace those copies. Apply the two phase
data attributes and the updated `add_job` method to each application's template,
including the actual-destination list check, then deliver that application
normally. Adopt email routing and exclusions in the staged order documented in
`Wingman::Role::EmailRecovery`; this form fix does not move existing jobs or
repair unsafe exclusions. No consumer application is changed here.

## Ended session authentication

`author.t/rest_ended_session.t` sends generated mutations through the actual
Dancer PSGI app with the runner's isolated MySQL and cache. Sessions past their
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
mutation through the actual Dancer PSGI app with the runner's isolated MySQL and
cache. Each returns the 401 login error instead of a 500 and removes the session's
cache entry. `extend` and SSO `check_permissions` end a session whose user no
longer resolves, so Wing::Web's `get_session` returns no session either.

## Account route permissions

`author.t/rest_route_permissions.t` sends real HTTP requests through the actual
built-in User and APIKey routes with the runner's isolated MySQL and cache. The
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
with the runner's isolated MySQL and cache, and counts `users` queries through
DBIx::Class's debug callback. A repeat request reads its user from the session's
cached `user_data` with no `users` query. A password change, deactivation or
deletion still ends every session of the user, a missing `user-changed-<id>`
marker reloads from the database, and a password change held uncommitted on a
second connection ends the sessions once committed, even after a no-op update
of the same user. A session uses the `user_data` it read together with its
`user_change_seen`, so an older session write landing later is not trusted.

User `update` calls that change a column, and `delete`, write the marker with no
expiry. A user with no marker is read from the database on every request until
its next change or login. Inside a transaction
the marker is prefixed `uncommitted-`, and sessions read that user from the
database on every request until the next committed change, because Wing cannot
tell when the transaction commits. User changes made outside DBIx::Class row
`update` or `delete` (resultset `update`, raw SQL, another application) write no
marker; after such a change, remove `user-changed-<id>` from the cache so sessions
reload the user.

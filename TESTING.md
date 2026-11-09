# Testing

The author tests live in `author.t`. Run them with the Perl runner, naming one or
more tests, or one slice of the whole suite:

```
perl author.t/run.pl author.t/user.t
perl author.t/run.pl --slice 1/8
```

## Prerequisites

- Perl with Wing's Perl dependencies and the author-test modules, both installed by
  `bin/setup/03_install_perl_modules.sh`.
- A running MySQL server and a running beanstalkd. If either is down, the tests
  fail; start it and rerun. Beanstalkd is at the address in
  `author.t/etc/test.conf`.
- `etc/local.conf`, this machine's untracked, gitignored settings. Its `db` entry
  says how to reach the dev MySQL: the DSN, which must name the `testwing`
  database and gives `mysql_socket`, or `host` and `port`, then the user, the
  password and the connection options. The test database lives there, and tenant
  databases are created on the same server. For example:

  ```
  {
     "db" : [
        "DBI:mysql:database=testwing;mysql_socket=/path/to/mysql.sock",
        "testwing",
        "testwing",
        { "mysql_enable_utf8" : 1 },
        { "quote_names" : 1 }
     ]
  }
  ```

  The runner fails and names the file when it is missing or MySQL cannot be
  reached through it.
- The test database and account, created once as the MySQL root user:

  ```
  mysql -uroot < author.t/bin/createdb.sql
  ```

  The `testwing` account can reach only `testwing` and databases named
  `testwing_*`.

## What the runner does

The runner sets `WING_HOME`, `WING_APP`, `WING_OWNER` and `WING_CONFIG` for the tests and
removes any other `WING_*` variables from their environment. It deploys the
TestWing schema into `testwing` once per run. Before each test file it empties
every table, drops `testwing_*` databases, deletes jobs in the `wingman_test` tube
and tubes named `wingman_test.*`, and starts a fresh cache. When the run ends, even
after a failure or interrupt, it drops the schema and the `testwing_*` databases
and clears those tubes again. Other tubes on the broker are left alone.

Only one run at a time can use the test database; a second run waits for the
first to finish.

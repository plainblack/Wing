-- Convert schema '/data/Wing/author.t/dbicdh/_source/deploy/5/001-auto.yml' to '/data/Wing/author.t/dbicdh/_source/deploy/4/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE companies DROP COLUMN private_info;

;

COMMIT;


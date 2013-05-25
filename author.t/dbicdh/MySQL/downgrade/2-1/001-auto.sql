-- Convert schema '/data/Wing/author.t/dbicdh/_source/deploy/2/001-auto.yml' to '/data/Wing/author.t/dbicdh/_source/deploy/1/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE companies DROP COLUMN web_url;

;

COMMIT;


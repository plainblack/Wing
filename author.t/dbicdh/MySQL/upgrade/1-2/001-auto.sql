-- Convert schema '/data/Wing/author.t/dbicdh/_source/deploy/1/001-auto.yml' to '/data/Wing/author.t/dbicdh/_source/deploy/2/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE companies ADD COLUMN web_url varchar(255);

;

COMMIT;


-- Convert schema '/data/Wing/author.t/dbicdh/_source/deploy/3/001-auto.yml' to '/data/Wing/author.t/dbicdh/_source/deploy/2/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE sites DROP FOREIGN KEY sites_fk_user_id;

;
DROP TABLE sites;

;

COMMIT;


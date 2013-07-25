-- Convert schema '/data/Wing/author.t/dbicdh/_source/deploy/3/001-auto.yml' to '/data/Wing/author.t/dbicdh/_source/deploy/2/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE acquisitions DROP FOREIGN KEY acquisitions_fk_user_id;

;
DROP TABLE acquisitions;

;

COMMIT;


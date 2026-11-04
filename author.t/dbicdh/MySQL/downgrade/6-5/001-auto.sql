-- Convert schema '/System/Volumes/Data/data/Wing/author.t/dbicdh/_source/deploy/6/001-auto.yml' to '/System/Volumes/Data/data/Wing/author.t/dbicdh/_source/deploy/5/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE users DROP INDEX idx_date_created,
                  DROP INDEX idx_date_updated,
                  DROP COLUMN no_email,
                  DROP COLUMN facebook_token,
                  DROP COLUMN last_ip,
                  DROP COLUMN permanently_deactivated,
                  DROP COLUMN facebook_uid,
                  ENGINE=InnoDB;

;

COMMIT;


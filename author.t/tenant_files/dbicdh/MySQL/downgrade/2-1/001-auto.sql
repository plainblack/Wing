-- Convert schema '/System/Volumes/Data/data/Wing/author.t/tenant_files/dbicdh/_source/deploy/2/001-auto.yml' to '/System/Volumes/Data/data/Wing/author.t/tenant_files/dbicdh/_source/deploy/1/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE api_key ENGINE=InnoDB;

;
ALTER TABLE api_key_permissions ENGINE=InnoDB;

;
ALTER TABLE users DROP INDEX idx_date_created,
                  DROP INDEX idx_date_updated,
                  DROP COLUMN no_email,
                  DROP COLUMN permanently_deactivated,
                  DROP COLUMN facebook_uid,
                  DROP COLUMN facebook_token,
                  DROP COLUMN last_ip,
                  CHANGE COLUMN master_user_id master_user_id varchar(36) NOT NULL,
                  CHANGE COLUMN real_name real_name varchar(255) NOT NULL DEFAULT '',
                  CHANGE COLUMN password password char(50) NOT NULL,
                  ENGINE=InnoDB;

;

COMMIT;


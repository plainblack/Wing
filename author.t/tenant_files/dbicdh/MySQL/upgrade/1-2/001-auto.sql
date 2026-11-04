-- Convert schema '/System/Volumes/Data/data/Wing/author.t/tenant_files/dbicdh/_source/deploy/1/001-auto.yml' to '/System/Volumes/Data/data/Wing/author.t/tenant_files/dbicdh/_source/deploy/2/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE api_key ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

;
ALTER TABLE api_key_permissions ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

;
ALTER TABLE users ADD COLUMN no_email tinyint NOT NULL DEFAULT 0,
                  ADD COLUMN permanently_deactivated tinyint NOT NULL DEFAULT 0,
                  ADD COLUMN facebook_uid bigint NULL,
                  ADD COLUMN facebook_token varchar(100) NULL,
                  ADD COLUMN last_ip varchar(20) NULL,
                  CHANGE COLUMN master_user_id master_user_id varchar(36) NULL,
                  CHANGE COLUMN password password char(50) NULL,
                  CHANGE COLUMN real_name real_name varchar(255) NULL DEFAULT '',
                  ADD INDEX idx_date_created (date_created),
                  ADD INDEX idx_date_updated (date_updated),
                  ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

;

COMMIT;


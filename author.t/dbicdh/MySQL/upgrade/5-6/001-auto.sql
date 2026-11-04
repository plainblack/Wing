-- Convert schema '/System/Volumes/Data/data/Wing/author.t/dbicdh/_source/deploy/5/001-auto.yml' to '/System/Volumes/Data/data/Wing/author.t/dbicdh/_source/deploy/6/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE users ADD COLUMN no_email tinyint NOT NULL DEFAULT 0,
                  ADD COLUMN facebook_token varchar(100) NULL,
                  ADD COLUMN last_ip varchar(20) NULL,
                  ADD COLUMN permanently_deactivated tinyint NOT NULL DEFAULT 0,
                  ADD COLUMN facebook_uid bigint NULL,
                  ADD INDEX idx_date_created (date_created),
                  ADD INDEX idx_date_updated (date_updated),
                  ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

;

COMMIT;


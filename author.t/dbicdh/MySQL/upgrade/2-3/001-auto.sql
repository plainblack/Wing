-- Convert schema '/data/Wing/author.t/dbicdh/_source/deploy/2/001-auto.yml' to '/data/Wing/author.t/dbicdh/_source/deploy/3/001-auto.yml':;

;
BEGIN;

;
SET foreign_key_checks=0;

;
CREATE TABLE `sites` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `database_name` varchar(50) NOT NULL DEFAULT '0',
  `trashed` tinyint NOT NULL DEFAULT 0,
  `name` varchar(60) NOT NULL,
  `user_id` char(36) NOT NULL,
  `hostname` varchar(255) NOT NULL,
  `shortname` varchar(50) NOT NULL,
  INDEX `sites_idx_user_id` (`user_id`),
  INDEX `idx_date_created` (`date_created`),
  INDEX `idx_date_updated` (`date_updated`),
  INDEX `idx_find_by_shortname` (`shortname`, `trashed`),
  INDEX `idx_find_by_hostname` (`hostname`, `trashed`),
  INDEX `idx_hostname` (`hostname`),
  PRIMARY KEY (`id`),
  UNIQUE `sites_database_name` (`database_name`),
  UNIQUE `sites_shortname` (`shortname`),
  CONSTRAINT `sites_fk_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB;

;
SET foreign_key_checks=1;

;

COMMIT;


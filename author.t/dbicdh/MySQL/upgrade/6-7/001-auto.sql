-- Convert schema '/System/Volumes/Data/data/Wing/author.t/dbicdh/_source/deploy/6/001-auto.yml' to '/System/Volumes/Data/data/Wing/author.t/dbicdh/_source/deploy/7/001-auto.yml':;

;
BEGIN;

;
SET foreign_key_checks=0;

;
CREATE TABLE `ideacomments` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `idea_id` char(36) NOT NULL,
  `comment` mediumtext NOT NULL,
  `likes` mediumblob NULL,
  `like_count` integer NOT NULL DEFAULT 0,
  `user_id` char(36) NOT NULL,
  INDEX `ideacomments_idx_idea_id` (`idea_id`),
  INDEX `ideacomments_idx_user_id` (`user_id`),
  INDEX `idx_date_created` (`date_created`),
  INDEX `idx_date_updated` (`date_updated`),
  PRIMARY KEY (`id`),
  CONSTRAINT `ideacomments_fk_idea_id` FOREIGN KEY (`idea_id`) REFERENCES `ideas` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `ideacomments_fk_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

;
CREATE TABLE `ideaopinions` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `opinion` varchar(4) NOT NULL,
  `idea_id` char(36) NOT NULL,
  `user_id` char(36) NOT NULL,
  INDEX `ideaopinions_idx_idea_id` (`idea_id`),
  INDEX `ideaopinions_idx_user_id` (`user_id`),
  INDEX `idx_hasvoted` (`idea_id`, `user_id`),
  INDEX `idx_opinion` (`opinion`),
  PRIMARY KEY (`id`),
  CONSTRAINT `ideaopinions_fk_idea_id` FOREIGN KEY (`idea_id`) REFERENCES `ideas` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `ideaopinions_fk_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB;

;
CREATE TABLE `ideas` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `subscription_count` integer NULL DEFAULT 0,
  `description` text NOT NULL,
  `yes` bigint NULL DEFAULT 0,
  `locked_status` varchar(20) NOT NULL DEFAULT 'Unlocked',
  `locked` tinyint NULL DEFAULT 0,
  `comment_count` integer NULL DEFAULT 0,
  `skip` bigint NULL DEFAULT 0,
  `name` varchar(60) NOT NULL,
  `merged_into_id` char(36) NULL,
  `uri_part` varchar(60) NOT NULL,
  `user_id` char(36) NOT NULL,
  INDEX `ideas_idx_merged_into_id` (`merged_into_id`),
  INDEX `ideas_idx_user_id` (`user_id`),
  INDEX `idx_date_created` (`date_created`),
  INDEX `idx_date_updated` (`date_updated`),
  FULLTEXT INDEX `idxft_name_description` (`name`, `description`),
  INDEX `idx_yes` (`yes`),
  INDEX `idx_skip` (`skip`),
  INDEX `idx_name` (`name`),
  PRIMARY KEY (`id`),
  UNIQUE `ideas_uri_part` (`uri_part`),
  CONSTRAINT `ideas_fk_merged_into_id` FOREIGN KEY (`merged_into_id`) REFERENCES `ideas` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ideas_fk_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

;
CREATE TABLE `ideasubscriptions` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `idea_id` char(36) NOT NULL,
  `user_id` char(36) NOT NULL,
  INDEX `ideasubscriptions_idx_idea_id` (`idea_id`),
  INDEX `ideasubscriptions_idx_user_id` (`user_id`),
  INDEX `idx_date_created` (`date_created`),
  INDEX `idx_date_updated` (`date_updated`),
  PRIMARY KEY (`id`),
  CONSTRAINT `ideasubscriptions_fk_idea_id` FOREIGN KEY (`idea_id`) REFERENCES `ideas` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `ideasubscriptions_fk_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

;
CREATE TABLE `trends_logs` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `name` varchar(60) NOT NULL,
  `value` float(15, 2) NOT NULL,
  `note` text NULL,
  INDEX `idx_date_name_value` (`date_created`, `name`, `value`),
  INDEX `idx_name` (`name`),
  PRIMARY KEY (`id`)
);

;
CREATE TABLE `trendsreports` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `name` varchar(60) NOT NULL,
  `fields` mediumblob NULL,
  INDEX `idx_date_created` (`date_created`),
  INDEX `idx_date_updated` (`date_updated`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

;
SET foreign_key_checks=1;

;
ALTER TABLE users ADD COLUMN auditor tinyint NOT NULL DEFAULT 0;

;

COMMIT;


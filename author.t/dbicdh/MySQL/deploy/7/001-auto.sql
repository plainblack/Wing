--
-- Created by SQL::Translator::Producer::MySQL
-- Created on Sat Nov  7 22:38:53 2026
--
;
SET foreign_key_checks=0;
--
-- Table: `companies`
--
CREATE TABLE `companies` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `web_url` varchar(255) NULL,
  `private_info` varchar(255) NULL,
  `name` varchar(60) NOT NULL,
  INDEX `idx_date_created` (`date_created`),
  INDEX `idx_date_updated` (`date_updated`),
  PRIMARY KEY (`id`),
  UNIQUE `companies_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;
--
-- Table: `trends_logs`
--
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
--
-- Table: `trendsreports`
--
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
--
-- Table: `users`
--
CREATE TABLE `users` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `auditor` tinyint NOT NULL DEFAULT 0,
  `facebook_uid` bigint NULL,
  `admin` tinyint NOT NULL DEFAULT 0,
  `email` varchar(255) NULL,
  `last_ip` varchar(20) NULL,
  `no_email` tinyint NOT NULL DEFAULT 0,
  `use_as_display_name` varchar(10) NULL DEFAULT 'username',
  `password` char(50) NULL,
  `permanently_deactivated` tinyint NOT NULL DEFAULT 0,
  `username` varchar(30) NOT NULL,
  `password_type` varchar(10) NOT NULL DEFAULT 'bcrypt',
  `facebook_token` varchar(100) NULL,
  `password_salt` char(16) NOT NULL DEFAULT 'abcdefghijklmnop',
  `real_name` varchar(255) NULL DEFAULT '',
  `developer` tinyint NOT NULL DEFAULT 0,
  `last_login` datetime NOT NULL,
  INDEX `idx_date_created` (`date_created`),
  INDEX `idx_date_updated` (`date_updated`),
  INDEX `idx_search` (`real_name`, `username`, `email`),
  PRIMARY KEY (`id`),
  UNIQUE `users_email` (`email`),
  UNIQUE `users_username` (`username`)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;
--
-- Table: `api_key`
--
CREATE TABLE `api_key` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `reason` varchar(255) NULL,
  `private_key` char(36) NULL,
  `name` varchar(30) NOT NULL,
  `uri` varchar(255) NULL,
  `user_id` char(36) NOT NULL,
  INDEX `api_key_idx_user_id` (`user_id`),
  INDEX `idx_date_created` (`date_created`),
  INDEX `idx_date_updated` (`date_updated`),
  PRIMARY KEY (`id`),
  UNIQUE `api_key_name` (`name`),
  CONSTRAINT `api_key_fk_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;
--
-- Table: `employees`
--
CREATE TABLE `employees` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `salary` integer NULL,
  `name` varchar(60) NOT NULL,
  `title` varchar(30) NULL,
  `company_id` char(36) NULL,
  INDEX `employees_idx_company_id` (`company_id`),
  INDEX `idx_date_created` (`date_created`),
  INDEX `idx_date_updated` (`date_updated`),
  PRIMARY KEY (`id`),
  CONSTRAINT `employees_fk_company_id` FOREIGN KEY (`company_id`) REFERENCES `companies` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;
--
-- Table: `ideas`
--
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
--
-- Table: `sites`
--
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
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;
--
-- Table: `api_key_permissions`
--
CREATE TABLE `api_key_permissions` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `permission` varchar(30) NOT NULL,
  `api_key_id` char(36) NOT NULL,
  `user_id` char(36) NOT NULL,
  INDEX `api_key_permissions_idx_api_key_id` (`api_key_id`),
  INDEX `api_key_permissions_idx_user_id` (`user_id`),
  INDEX `idx_date_created` (`date_created`),
  INDEX `idx_date_updated` (`date_updated`),
  INDEX `idx_apikey_user` (`api_key_id`, `user_id`),
  PRIMARY KEY (`id`),
  CONSTRAINT `api_key_permissions_fk_api_key_id` FOREIGN KEY (`api_key_id`) REFERENCES `api_key` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `api_key_permissions_fk_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;
--
-- Table: `equipment`
--
CREATE TABLE `equipment` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `name` varchar(60) NOT NULL,
  `employee_id` char(36) NOT NULL,
  INDEX `equipment_idx_employee_id` (`employee_id`),
  INDEX `idx_date_created` (`date_created`),
  INDEX `idx_date_updated` (`date_updated`),
  PRIMARY KEY (`id`),
  CONSTRAINT `equipment_fk_employee_id` FOREIGN KEY (`employee_id`) REFERENCES `employees` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;
--
-- Table: `ideacomments`
--
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
--
-- Table: `ideaopinions`
--
CREATE TABLE `ideaopinions` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `opinion` varchar(4) NOT NULL,
  `idea_id` char(36) NOT NULL,
  `user_id` char(36) NOT NULL,
  INDEX `ideaopinions_idx_idea_id` (`idea_id`),
  INDEX `ideaopinions_idx_user_id` (`user_id`),
  INDEX `idx_date_created` (`date_created`),
  INDEX `idx_date_updated` (`date_updated`),
  INDEX `idx_hasvoted` (`idea_id`, `user_id`),
  INDEX `idx_opinion` (`opinion`),
  PRIMARY KEY (`id`),
  CONSTRAINT `ideaopinions_fk_idea_id` FOREIGN KEY (`idea_id`) REFERENCES `ideas` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `ideaopinions_fk_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;
--
-- Table: `ideasubscriptions`
--
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
SET foreign_key_checks=1;

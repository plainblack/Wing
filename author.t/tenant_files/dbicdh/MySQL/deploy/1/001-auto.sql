-- 
-- Created by SQL::Translator::Producer::MySQL
-- Created on Thu Jul 25 14:37:49 2013
-- 
;
SET foreign_key_checks=0;
--
-- Table: `users`
--
CREATE TABLE `users` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `admin` tinyint NOT NULL DEFAULT 0,
  `real_name` varchar(255) NOT NULL DEFAULT '',
  `password_type` varchar(10) NOT NULL DEFAULT 'bcrypt',
  `password_salt` char(16) NOT NULL DEFAULT 'abcdefghijklmnop',
  `username` varchar(30) NOT NULL,
  `email` varchar(255) NULL,
  `password` char(50) NOT NULL,
  `use_as_display_name` varchar(10) NULL DEFAULT 'username',
  `developer` tinyint NOT NULL DEFAULT 0,
  `last_login` datetime NOT NULL,
  INDEX `idx_search` (`real_name`, `username`, `email`),
  PRIMARY KEY (`id`),
  UNIQUE `users_email` (`email`),
  UNIQUE `users_username` (`username`)
) ENGINE=InnoDB;
--
-- Table: `api_key`
--
CREATE TABLE `api_key` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `private_key` char(36) NULL,
  `reason` varchar(255) NULL,
  `name` varchar(30) NOT NULL,
  `uri` varchar(255) NULL,
  `user_id` char(36) NOT NULL,
  INDEX `api_key_idx_user_id` (`user_id`),
  INDEX `idx_date_created` (`date_created`),
  INDEX `idx_date_updated` (`date_updated`),
  PRIMARY KEY (`id`),
  UNIQUE `api_key_name` (`name`),
  CONSTRAINT `api_key_fk_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;
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
) ENGINE=InnoDB;
SET foreign_key_checks=1;

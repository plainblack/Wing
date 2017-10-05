-- Convert schema '/data/Wing/author.t/dbicdh/_source/deploy/4/001-auto.yml' to '/data/Wing/author.t/dbicdh/_source/deploy/3/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE api_key ENGINE=InnoDB;

;
ALTER TABLE api_key_permissions ENGINE=InnoDB;

;
ALTER TABLE companies ENGINE=InnoDB;

;
ALTER TABLE employees ENGINE=InnoDB;

;
ALTER TABLE equipment ENGINE=InnoDB;

;
ALTER TABLE sites ENGINE=InnoDB;

;
ALTER TABLE users CHANGE COLUMN real_name real_name varchar(255) NOT NULL DEFAULT '',
                  CHANGE COLUMN password password char(50) NOT NULL;

;

COMMIT;


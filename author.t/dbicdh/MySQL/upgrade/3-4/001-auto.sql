-- Convert schema '/data/Wing/author.t/dbicdh/_source/deploy/3/001-auto.yml' to '/data/Wing/author.t/dbicdh/_source/deploy/4/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE api_key ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

;
ALTER TABLE api_key_permissions ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

;
ALTER TABLE companies ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

;
ALTER TABLE employees ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

;
ALTER TABLE equipment ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

;
ALTER TABLE sites ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

;
ALTER TABLE users CHANGE COLUMN real_name real_name varchar(255) NULL DEFAULT '',
                  CHANGE COLUMN password password char(50) NULL;

;

COMMIT;


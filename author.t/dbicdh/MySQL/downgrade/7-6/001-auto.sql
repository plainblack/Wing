-- Convert schema '/System/Volumes/Data/data/Wing/author.t/dbicdh/_source/deploy/7/001-auto.yml' to '/System/Volumes/Data/data/Wing/author.t/dbicdh/_source/deploy/6/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE users DROP COLUMN auditor;

;
DROP TABLE trends_logs;

;
DROP TABLE trendsreports;

;
ALTER TABLE ideas DROP FOREIGN KEY ideas_fk_merged_into_id,
                  DROP FOREIGN KEY ideas_fk_user_id;

;
DROP TABLE ideas;

;
ALTER TABLE ideacomments DROP FOREIGN KEY ideacomments_fk_idea_id,
                         DROP FOREIGN KEY ideacomments_fk_user_id;

;
DROP TABLE ideacomments;

;
ALTER TABLE ideaopinions DROP FOREIGN KEY ideaopinions_fk_idea_id,
                         DROP FOREIGN KEY ideaopinions_fk_user_id;

;
DROP TABLE ideaopinions;

;
ALTER TABLE ideasubscriptions DROP FOREIGN KEY ideasubscriptions_fk_idea_id,
                              DROP FOREIGN KEY ideasubscriptions_fk_user_id;

;
DROP TABLE ideasubscriptions;

;

COMMIT;


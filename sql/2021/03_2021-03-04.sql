ALTER TABLE users ADD COLUMN compname char(128) DEFAULT '';
ALTER TABLE users ADD INDEX compname (compname);

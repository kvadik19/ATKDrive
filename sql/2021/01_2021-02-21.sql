ALTER TABLE users ADD COLUMN fullname char(128) DEFAULT '';
ALTER TABLE users ADD INDEX fullname (fullname);

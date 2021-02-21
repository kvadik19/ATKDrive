ALTER TABLE users ADD COLUMN name char(20) DEFAULT '';
ALTER TABLE users ADD INDEX name (name);

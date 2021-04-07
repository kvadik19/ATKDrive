ALTER TABLE users ADD COLUMN code char(9) DEFAULT '';
ALTER TABLE users ADD INDEX code (code);

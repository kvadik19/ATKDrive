ALTER TABLE users ADD COLUMN phone char(20) DEFAULT '';
ALTER TABLE users ADD INDEX phone (phone);

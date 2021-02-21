ALTER TABLE users ADD COLUMN amount dec(10,2);
ALTER TABLE users ADD INDEX amount (amount);

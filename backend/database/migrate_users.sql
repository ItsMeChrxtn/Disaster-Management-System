USE disaster_map;
ALTER TABLE users MODIFY status ENUM('active','suspended','disabled','deleted') NOT NULL DEFAULT 'active';
UPDATE users SET status='disabled' WHERE status='suspended';
ALTER TABLE users MODIFY status ENUM('active','disabled','deleted') NOT NULL DEFAULT 'active';


-- Run only when upgrading a database created by the original schema.
USE disaster_map;
ALTER TABLE users CHANGE name fullname VARCHAR(150) NOT NULL;
ALTER TABLE users CHANGE password_hash password VARCHAR(255) NOT NULL;
ALTER TABLE users ADD COLUMN address VARCHAR(255) NULL AFTER phone;
ALTER TABLE users ADD COLUMN barangay VARCHAR(120) NULL AFTER address;
ALTER TABLE users MODIFY role ENUM('admin','sub_admin','subadmin','resident') NOT NULL DEFAULT 'resident';
UPDATE users SET role='subadmin' WHERE role='sub_admin';
ALTER TABLE users MODIFY role ENUM('admin','subadmin','resident') NOT NULL DEFAULT 'resident';
DROP TABLE IF EXISTS auth_tokens;
CREATE TABLE user_sessions (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, jti CHAR(32) NOT NULL UNIQUE, user_id BIGINT UNSIGNED NOT NULL,
  user_agent VARCHAR(255) NULL, ip_address VARCHAR(45) NULL, expires_at TIMESTAMP NOT NULL, revoked_at TIMESTAMP NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, CONSTRAINT fk_session_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_session_validation (jti,user_id,expires_at,revoked_at)
) ENGINE=InnoDB;
CREATE TABLE password_reset_tokens (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, user_id BIGINT UNSIGNED NOT NULL, token_hash CHAR(64) NOT NULL UNIQUE,
  expires_at TIMESTAMP NOT NULL, used_at TIMESTAMP NULL, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_reset_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE, INDEX idx_reset_validation (token_hash,expires_at,used_at)
) ENGINE=InnoDB;

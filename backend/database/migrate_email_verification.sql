-- Adds storage for the registration email-verification flow (users.email_verified_at already exists in schema.sql).
USE disaster_map;
CREATE TABLE email_verification_tokens (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, user_id BIGINT UNSIGNED NOT NULL, token_hash CHAR(64) NOT NULL UNIQUE,
  expires_at TIMESTAMP NOT NULL, used_at TIMESTAMP NULL, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_verify_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE, INDEX idx_verify_validation (token_hash,expires_at,used_at)
) ENGINE=InnoDB;
-- Grandfather in accounts that existed before this feature shipped, so nobody already active gets locked out.
UPDATE users SET email_verified_at = created_at WHERE email_verified_at IS NULL;

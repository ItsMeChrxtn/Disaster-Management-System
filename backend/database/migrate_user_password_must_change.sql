ALTER TABLE users
  ADD COLUMN password_must_change TINYINT(1) NOT NULL DEFAULT 0 AFTER email_verified_at;

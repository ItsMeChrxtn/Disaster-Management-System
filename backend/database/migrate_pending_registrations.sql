-- Registrations are held here until the email is verified; only then does a real users row get created.
-- email_verification_tokens is no longer used by the register/verify flow and can stay unused.
USE disaster_map;
CREATE TABLE pending_registrations (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  municipality_id BIGINT UNSIGNED NULL,
  fullname VARCHAR(150) NOT NULL,
  email VARCHAR(190) NOT NULL,
  password VARCHAR(255) NOT NULL,
  phone VARCHAR(30) NULL,
  address VARCHAR(255) NULL,
  barangay VARCHAR(120) NULL,
  code_hash CHAR(64) NOT NULL,
  expires_at TIMESTAMP NOT NULL DEFAULT '2000-01-01 00:00:00',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_pending_email (email)
) ENGINE=InnoDB;

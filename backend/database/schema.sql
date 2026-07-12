CREATE DATABASE IF NOT EXISTS disaster_map CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE disaster_map;

CREATE TABLE municipalities (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  municipality_name VARCHAR(120) NOT NULL, description TEXT NULL,
  center_lat DECIMAL(10,7) NULL, center_lng DECIMAL(10,7) NULL,
  status ENUM('active','inactive') NOT NULL DEFAULT 'active', created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_municipality_name (municipality_name)
) ENGINE=InnoDB;

CREATE TABLE users (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, municipality_id BIGINT UNSIGNED NULL,
  fullname VARCHAR(150) NOT NULL, email VARCHAR(190) NOT NULL UNIQUE, password VARCHAR(255) NOT NULL,
  phone VARCHAR(30) NULL, address VARCHAR(255) NULL, barangay VARCHAR(120) NULL,
  role ENUM('admin','subadmin','resident') NOT NULL DEFAULT 'resident',
  status ENUM('active','disabled','deleted') NOT NULL DEFAULT 'active', email_verified_at TIMESTAMP NULL,
  password_must_change TINYINT(1) NOT NULL DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_user_municipality FOREIGN KEY (municipality_id) REFERENCES municipalities(id) ON DELETE SET NULL,
  INDEX idx_users_scope (municipality_id,role,status)
) ENGINE=InnoDB;

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

CREATE TABLE hazards (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, municipality_id BIGINT UNSIGNED NULL,
  hazard_name VARCHAR(180) NOT NULL,
  hazard_type VARCHAR(80) NOT NULL,
  risk_level ENUM('low','moderate','high','critical') NOT NULL, description TEXT NULL, geojson_data JSON NOT NULL,
  status ENUM('active','archived') NOT NULL DEFAULT 'active', created_by BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_hazard_municipality FOREIGN KEY (municipality_id) REFERENCES municipalities(id) ON DELETE SET NULL,
  CONSTRAINT fk_hazard_user FOREIGN KEY (created_by) REFERENCES users(id), INDEX idx_hazard_map (status,hazard_type,risk_level,municipality_id),
  FULLTEXT KEY idx_hazard_search (hazard_name,description)
) ENGINE=InnoDB;

CREATE TABLE alerts (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, title VARCHAR(180) NOT NULL,
  alert_type ENUM('weather_alert','flood_alert','earthquake_alert','storm_surge_alert','emergency_alert') NOT NULL,
  alert_level ENUM('info','advisory','warning','critical') NOT NULL, message TEXT NOT NULL, municipality_id BIGINT UNSIGNED NULL,
  status ENUM('draft','sent','deleted') NOT NULL DEFAULT 'draft', sent_at TIMESTAMP NULL,
  created_by BIGINT UNSIGNED NOT NULL, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_alert_municipality FOREIGN KEY (municipality_id) REFERENCES municipalities(id) ON DELETE SET NULL,
  CONSTRAINT fk_alert_user FOREIGN KEY (created_by) REFERENCES users(id), INDEX idx_alert_delivery (status,municipality_id,sent_at)
) ENGINE=InnoDB;

CREATE TABLE alert_reads (
  alert_id BIGINT UNSIGNED NOT NULL, user_id BIGINT UNSIGNED NOT NULL, read_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (alert_id,user_id), CONSTRAINT fk_alert_read_alert FOREIGN KEY (alert_id) REFERENCES alerts(id) ON DELETE CASCADE,
  CONSTRAINT fk_alert_read_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE notifications (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, user_id BIGINT UNSIGNED NULL, alert_id BIGINT UNSIGNED NULL,
  notification_type ENUM('alert','warning','announcement','system_update') NOT NULL DEFAULT 'alert',
  title VARCHAR(180) NOT NULL, message TEXT NOT NULL, is_read TINYINT(1) NOT NULL DEFAULT 0, read_at TIMESTAMP NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_notification_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_notification_alert FOREIGN KEY (alert_id) REFERENCES alerts(id) ON DELETE CASCADE,
  INDEX idx_notification_delivery (user_id,is_read,created_at)
) ENGINE=InnoDB;

CREATE TABLE weather_updates (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, municipality_id BIGINT UNSIGNED NULL,
  condition_text VARCHAR(120) NOT NULL, temperature_c DECIMAL(5,2) NULL, rainfall_mm DECIMAL(8,2) NULL,
  advisory_level ENUM('normal','advisory','warning','critical') NOT NULL DEFAULT 'normal', source VARCHAR(180) NULL,
  observed_at TIMESTAMP NOT NULL, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_weather_municipality FOREIGN KEY (municipality_id) REFERENCES municipalities(id) ON DELETE CASCADE,
  INDEX idx_weather_scope (municipality_id,observed_at)
) ENGINE=InnoDB;

CREATE TABLE safe_zones (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, municipality_id BIGINT UNSIGNED NOT NULL,
  safezone_name VARCHAR(180) NOT NULL, address VARCHAR(255) NULL, latitude DECIMAL(10,7) NOT NULL, longitude DECIMAL(10,7) NOT NULL,
  capacity INT UNSIGNED NULL, contact_person VARCHAR(120) NULL, contact_number VARCHAR(30) NULL, description TEXT NULL, status ENUM('active','inactive') NOT NULL DEFAULT 'active', created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_safe_zone_municipality FOREIGN KEY (municipality_id) REFERENCES municipalities(id) ON DELETE CASCADE,
  INDEX idx_safe_zone_scope (municipality_id,status)
) ENGINE=InnoDB;

CREATE TABLE evacuation_centers (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, municipality_id BIGINT UNSIGNED NOT NULL,
  center_name VARCHAR(180) NOT NULL, address VARCHAR(255) NOT NULL, contact_person VARCHAR(120) NULL, contact_number VARCHAR(30) NULL,
  capacity INT UNSIGNED NOT NULL, status ENUM('available','full','closed','under_maintenance','deleted') NOT NULL DEFAULT 'available',
  latitude DECIMAL(10,7) NOT NULL, longitude DECIMAL(10,7) NOT NULL, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_evacuation_center_municipality FOREIGN KEY (municipality_id) REFERENCES municipalities(id) ON DELETE CASCADE,
  INDEX idx_evacuation_center_scope (municipality_id,status)
) ENGINE=InnoDB;

CREATE TABLE evacuation_routes (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  municipality_id BIGINT UNSIGNED NULL,
  route_name VARCHAR(180) NOT NULL,
  start_location JSON NOT NULL,
  end_location JSON NOT NULL,
  geojson_data JSON NOT NULL,
  distance_km DECIMAL(10,2) NULL, estimated_travel_minutes INT UNSIGNED NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_route_municipality FOREIGN KEY (municipality_id) REFERENCES municipalities(id) ON DELETE SET NULL,
  INDEX idx_route_municipality (municipality_id)
) ENGINE=InnoDB;

CREATE TABLE historical_disasters (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(180) NOT NULL, disaster_type VARCHAR(80) NOT NULL, description TEXT NULL,
  municipality_id BIGINT UNSIGNED NULL, date_occurred DATE NOT NULL,
  casualties INT UNSIGNED NOT NULL DEFAULT 0, damages DECIMAL(15,2) NOT NULL DEFAULT 0,
  CONSTRAINT fk_historical_municipality FOREIGN KEY (municipality_id) REFERENCES municipalities(id) ON DELETE RESTRICT,
  INDEX idx_historical_report (date_occurred,municipality_id,disaster_type)
) ENGINE=InnoDB;

CREATE TABLE reports (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  report_type ENUM('hazard','alert','historical_disaster','evacuation_center') NOT NULL,
  generated_by BIGINT UNSIGNED NOT NULL,
  generated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  file_path VARCHAR(500) NOT NULL,
  CONSTRAINT fk_report_user FOREIGN KEY (generated_by) REFERENCES users(id),
  INDEX idx_report_history (generated_by,generated_at,report_type)
) ENGINE=InnoDB;

CREATE TABLE audit_logs (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, user_id BIGINT UNSIGNED NULL, action VARCHAR(100) NOT NULL,
  entity_type VARCHAR(80) NULL, entity_id BIGINT UNSIGNED NULL, metadata JSON NULL, ip_address VARCHAR(45) NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, INDEX idx_audit_entity (entity_type,entity_id), INDEX idx_audit_user (user_id,created_at),
  CONSTRAINT fk_audit_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- Disaster Map: complete MySQL 8+/MariaDB 10.4+ fresh-install schema
-- WARNING: This script drops and recreates application tables in `disaster_map`.
-- Sample account password: ChangeMe123! (change immediately after import)

CREATE DATABASE IF NOT EXISTS disaster_map
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE disaster_map;

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS=0;
DROP TABLE IF EXISTS audit_logs, alert_reads, password_reset_tokens, user_sessions,
  weather_updates, notifications, reports, historical_disasters, evacuation_routes, evacuation_centers,
  safe_zones, alerts, hazards, users, municipalities;
SET FOREIGN_KEY_CHECKS=1;

CREATE TABLE municipalities (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  municipality_name VARCHAR(120) NOT NULL,
  description TEXT NULL,
  center_lat DECIMAL(10,7) NULL,
  center_lng DECIMAL(10,7) NULL,
  status ENUM('active','inactive') NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_municipality_name (municipality_name),
  KEY idx_municipality_status (status),
  KEY idx_municipality_center (center_lat,center_lng)
) ENGINE=InnoDB;

CREATE TABLE users (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  municipality_id BIGINT UNSIGNED NULL,
  fullname VARCHAR(150) NOT NULL,
  email VARCHAR(190) NOT NULL,
  password VARCHAR(255) NOT NULL,
  phone VARCHAR(30) NULL,
  address VARCHAR(255) NULL,
  barangay VARCHAR(120) NULL,
  role ENUM('admin','subadmin','resident') NOT NULL DEFAULT 'resident',
  status ENUM('active','disabled','deleted') NOT NULL DEFAULT 'active',
  email_verified_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_user_email (email),
  KEY idx_users_scope (municipality_id,role,status),
  KEY idx_users_status_created (status,created_at),
  CONSTRAINT fk_user_municipality FOREIGN KEY (municipality_id)
    REFERENCES municipalities(id) ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB;

-- JWT session allow-list used for logout, revocation, and server-side validation.
CREATE TABLE user_sessions (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  jti CHAR(32) NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  user_agent VARCHAR(255) NULL,
  ip_address VARCHAR(45) NULL,
  expires_at TIMESTAMP NOT NULL,
  revoked_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_session_jti (jti),
  KEY idx_session_validation (jti,user_id,expires_at,revoked_at),
  KEY idx_session_user (user_id,created_at),
  CONSTRAINT fk_session_user FOREIGN KEY (user_id)
    REFERENCES users(id) ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE password_reset_tokens (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NOT NULL,
  token_hash CHAR(64) NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  used_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_reset_token_hash (token_hash),
  KEY idx_reset_validation (token_hash,expires_at,used_at),
  KEY idx_reset_user (user_id,created_at),
  CONSTRAINT fk_reset_user FOREIGN KEY (user_id)
    REFERENCES users(id) ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE hazards (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  municipality_id BIGINT UNSIGNED NULL,
  hazard_name VARCHAR(180) NOT NULL,
  hazard_type ENUM('flood_zone','storm_surge_area','earthquake_area','high_risk_area') NOT NULL,
  risk_level ENUM('low','moderate','high','critical') NOT NULL,
  description TEXT NULL,
  geojson_data JSON NOT NULL,
  status ENUM('active','archived') NOT NULL DEFAULT 'active',
  created_by BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_hazard_map (status,hazard_type,risk_level,municipality_id),
  KEY idx_hazard_creator (created_by,created_at),
  FULLTEXT KEY idx_hazard_search (hazard_name,description),
  CONSTRAINT fk_hazard_municipality FOREIGN KEY (municipality_id)
    REFERENCES municipalities(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT fk_hazard_user FOREIGN KEY (created_by)
    REFERENCES users(id) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE safe_zones (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  safezone_name VARCHAR(180) NOT NULL,
  municipality_id BIGINT UNSIGNED NOT NULL,
  address VARCHAR(255) NULL,
  latitude DECIMAL(10,7) NOT NULL,
  longitude DECIMAL(10,7) NOT NULL,
  capacity INT UNSIGNED NULL,
  description TEXT NULL,
  status ENUM('active','inactive') NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_safe_zone_scope (municipality_id,status),
  KEY idx_safe_zone_coordinates (latitude,longitude),
  CONSTRAINT fk_safe_zone_municipality FOREIGN KEY (municipality_id)
    REFERENCES municipalities(id) ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE evacuation_centers (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  center_name VARCHAR(180) NOT NULL,
  municipality_id BIGINT UNSIGNED NOT NULL,
  address VARCHAR(255) NOT NULL,
  contact_number VARCHAR(30) NULL,
  capacity INT UNSIGNED NOT NULL,
  status ENUM('available','full','closed','under_maintenance','deleted') NOT NULL DEFAULT 'available',
  latitude DECIMAL(10,7) NOT NULL,
  longitude DECIMAL(10,7) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_evacuation_center_scope (municipality_id,status),
  KEY idx_evacuation_center_coordinates (latitude,longitude),
  CONSTRAINT fk_evacuation_center_municipality FOREIGN KEY (municipality_id)
    REFERENCES municipalities(id) ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE evacuation_routes (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  route_name VARCHAR(180) NOT NULL,
  municipality_id BIGINT UNSIGNED NULL,
  start_location JSON NOT NULL,
  end_location JSON NOT NULL,
  geojson_data JSON NOT NULL,
  distance_km DECIMAL(10,2) NULL,
  estimated_travel_minutes INT UNSIGNED NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_route_municipality (municipality_id),
  CONSTRAINT fk_route_municipality FOREIGN KEY (municipality_id)
    REFERENCES municipalities(id) ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE weather_updates (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  municipality_id BIGINT UNSIGNED NULL,
  condition_text VARCHAR(120) NOT NULL,
  temperature_c DECIMAL(5,2) NULL,
  rainfall_mm DECIMAL(8,2) NULL,
  advisory_level ENUM('normal','advisory','warning','critical') NOT NULL DEFAULT 'normal',
  source VARCHAR(180) NULL,
  observed_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_weather_scope (municipality_id,observed_at),
  CONSTRAINT fk_weather_municipality FOREIGN KEY (municipality_id) REFERENCES municipalities(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE alerts (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(180) NOT NULL,
  alert_type ENUM('weather_alert','flood_alert','earthquake_alert','storm_surge_alert','emergency_alert') NOT NULL,
  alert_level ENUM('info','advisory','warning','critical') NOT NULL,
  message TEXT NOT NULL,
  municipality_id BIGINT UNSIGNED NULL,
  status ENUM('draft','sent','deleted') NOT NULL DEFAULT 'draft',
  sent_at TIMESTAMP NULL,
  created_by BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_alert_delivery (status,municipality_id,sent_at),
  KEY idx_alert_type_level (alert_type,alert_level,created_at),
  KEY idx_alert_creator (created_by,created_at),
  CONSTRAINT fk_alert_municipality FOREIGN KEY (municipality_id)
    REFERENCES municipalities(id) ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT fk_alert_user FOREIGN KEY (created_by)
    REFERENCES users(id) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- Per-resident notification read state.
CREATE TABLE alert_reads (
  alert_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  read_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (alert_id,user_id),
  KEY idx_alert_reads_user (user_id,read_at),
  CONSTRAINT fk_alert_read_alert FOREIGN KEY (alert_id)
    REFERENCES alerts(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_alert_read_user FOREIGN KEY (user_id)
    REFERENCES users(id) ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE notifications (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NULL,
  alert_id BIGINT UNSIGNED NULL,
  notification_type ENUM('alert','warning','announcement','system_update') NOT NULL DEFAULT 'alert',
  title VARCHAR(180) NOT NULL,
  message TEXT NOT NULL,
  is_read TINYINT(1) NOT NULL DEFAULT 0,
  read_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_notification_delivery (user_id,is_read,created_at),
  CONSTRAINT fk_notification_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_notification_alert FOREIGN KEY (alert_id) REFERENCES alerts(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE historical_disasters (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(180) NOT NULL,
  disaster_type VARCHAR(80) NOT NULL,
  description TEXT NULL,
  municipality_id BIGINT UNSIGNED NULL,
  date_occurred DATE NOT NULL,
  casualties INT UNSIGNED NOT NULL DEFAULT 0,
  damages DECIMAL(15,2) NOT NULL DEFAULT 0.00,
  KEY idx_historical_report (date_occurred,municipality_id,disaster_type),
  KEY idx_historical_type (disaster_type,date_occurred),
  FULLTEXT KEY idx_historical_search (title,description),
  CONSTRAINT fk_historical_municipality FOREIGN KEY (municipality_id)
    REFERENCES municipalities(id) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE reports (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  report_type ENUM('hazard','alert','historical_disaster','evacuation_center') NOT NULL,
  generated_by BIGINT UNSIGNED NOT NULL,
  generated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  file_path VARCHAR(500) NOT NULL,
  KEY idx_report_history (generated_by,generated_at,report_type),
  KEY idx_report_type_date (report_type,generated_at),
  CONSTRAINT fk_report_user FOREIGN KEY (generated_by)
    REFERENCES users(id) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE audit_logs (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT UNSIGNED NULL,
  action VARCHAR(100) NOT NULL,
  entity_type VARCHAR(80) NULL,
  entity_id BIGINT UNSIGNED NULL,
  metadata JSON NULL,
  ip_address VARCHAR(45) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_audit_entity (entity_type,entity_id,created_at),
  KEY idx_audit_user (user_id,created_at),
  CONSTRAINT fk_audit_user FOREIGN KEY (user_id)
    REFERENCES users(id) ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB;

START TRANSACTION;

INSERT INTO municipalities
  (id,municipality_name,description,center_lat,center_lng,status)
VALUES
  (1,'Bacoor City','Sample Cavite coastal city used for demonstration data.',14.4590300,120.9495500,'active'),
  (2,'Imus City','Sample Cavite city used for demonstration data.',14.4297200,120.9366700,'active'),
  (3,'Dasmarinas City','Sample Cavite city used for response-planning data.',14.3294400,120.9366700,'active');

-- All sample users use ChangeMe123!; the value below is a bcrypt hash.
INSERT INTO users
  (id,municipality_id,fullname,email,password,phone,address,barangay,role,status,email_verified_at)
VALUES
  (1,NULL,'PDRRMO Administrator','admin@example.gov.ph','$2y$10$QNnjUX9avYT5vT9WkOrs7eHq.Mk541k6fA/7JfilzRc4kq38OD1nm','09170000001','Provincial Capitol',NULL,'admin','active',CURRENT_TIMESTAMP),
  (2,1,'Bacoor CDRRMO','subadmin@example.gov.ph','$2y$10$QNnjUX9avYT5vT9WkOrs7eHq.Mk541k6fA/7JfilzRc4kq38OD1nm','09170000002','Bacoor Government Center','Poblacion','subadmin','active',CURRENT_TIMESTAMP),
  (3,1,'Juan Dela Cruz','resident@example.com','$2y$10$QNnjUX9avYT5vT9WkOrs7eHq.Mk541k6fA/7JfilzRc4kq38OD1nm','09170000003','12 Mabini Street','Poblacion','resident','active',CURRENT_TIMESTAMP),
  (4,2,'Maria Santos','maria@example.com','$2y$10$QNnjUX9avYT5vT9WkOrs7eHq.Mk541k6fA/7JfilzRc4kq38OD1nm','09170000004','8 Rizal Street','Central','resident','active',CURRENT_TIMESTAMP);

INSERT INTO hazards
  (id,municipality_id,hazard_name,hazard_type,risk_level,description,geojson_data,created_by,status)
VALUES
  (1,1,'Bacoor Flood Zone','flood_zone','high','Sample low-lying area for Cavite flood mapping demonstrations','{"type":"Polygon","coordinates":[[[120.938,14.445],[120.950,14.445],[120.950,14.455],[120.938,14.455],[120.938,14.445]]]}',1,'active'),
  (2,1,'Bacoor Coastal Storm Surge Area','storm_surge_area','critical','Sample coastal evacuation area for storm-surge demonstrations','{"type":"Polygon","coordinates":[[[120.905,14.475],[120.920,14.475],[120.920,14.485],[120.905,14.485],[120.905,14.475]]]}',2,'active'),
  (3,2,'Imus Earthquake Planning Area','earthquake_area','moderate','Sample earthquake planning area for structural and evacuation exercises','{"type":"Polygon","coordinates":[[[120.928,14.420],[120.940,14.420],[120.940,14.431],[120.928,14.431],[120.928,14.420]]]}',1,'active'),
  (4,3,'Dasmarinas High-Risk Area','high_risk_area','high','Sample high-risk point for Cavite planning demonstrations','{"type":"Point","coordinates":[120.936,14.329]}',1,'active');

INSERT INTO safe_zones
  (id,safezone_name,municipality_id,address,latitude,longitude,capacity,description,status)
VALUES
  (1,'Bacoor Civic Plaza',1,'Bacoor City, Cavite',14.4620000,120.9540000,500,'Sample open assembly area','active'),
  (2,'Imus Sports Field',2,'Imus City, Cavite',14.4350000,120.9420000,750,'Sample outdoor safe assembly area','active'),
  (3,'Dasmarinas Community Park',3,'Dasmarinas City, Cavite',14.3350000,120.9410000,300,'Sample elevated safe zone','active');

INSERT INTO evacuation_centers
  (id,center_name,municipality_id,address,contact_number,capacity,status,latitude,longitude)
VALUES
  (1,'Bacoor Evacuation School',1,'Bacoor City, Cavite','09171234567',800,'available',14.4640000,120.9560000),
  (2,'Imus Municipal Gym',2,'Imus City, Cavite','09172345678',1000,'available',14.4380000,120.9450000),
  (3,'Dasmarinas Evacuation School',3,'Dasmarinas City, Cavite','09173456789',450,'available',14.3370000,120.9440000);

INSERT INTO evacuation_routes
  (id,route_name,municipality_id,start_location,end_location,geojson_data)
VALUES
  (1,'Bacoor Flood Zone to Civic Plaza',1,'{"name":"Bacoor Flood Zone","latitude":14.450,"longitude":120.944}','{"name":"Bacoor Civic Plaza","latitude":14.462,"longitude":120.954}','{"type":"LineString","coordinates":[[120.944,14.450],[120.949,14.456],[120.954,14.462]]}'),
  (2,'Imus Center to Municipal Gym',2,'{"name":"Imus Center","latitude":14.430,"longitude":120.937}','{"name":"Imus Municipal Gym","latitude":14.438,"longitude":120.945}','{"type":"LineString","coordinates":[[120.937,14.430],[120.941,14.434],[120.945,14.438]]}');

INSERT INTO alerts
  (id,title,alert_type,alert_level,message,municipality_id,status,sent_at,created_by)
VALUES
  (1,'Heavy Rainfall Advisory','weather_alert','advisory','Monitor local waterways and prepare emergency supplies.',NULL,'sent',CURRENT_TIMESTAMP,1),
  (2,'Flood Warning for Riverside','flood_alert','warning','Residents in the Riverside Flood Zone should prepare for possible evacuation.',1,'sent',CURRENT_TIMESTAMP,2),
  (3,'Storm Surge Preparedness','storm_surge_alert','critical','Coastal residents must follow the official evacuation instructions immediately.',1,'draft',NULL,2);

INSERT INTO alert_reads (alert_id,user_id,read_at)
VALUES (1,3,CURRENT_TIMESTAMP);

INSERT INTO historical_disasters
  (id,title,disaster_type,description,municipality_id,date_occurred,casualties,damages)
VALUES
  (1,'Typhoon Salin Historical Record','Typhoon','Sample post-disaster record for reporting demonstrations.',1,'2022-10-29',3,12500000.00),
  (2,'Santa Maria Flood Event','Flood','Several low-lying roads were temporarily impassable.',2,'2023-07-18',0,2750000.00),
  (3,'Del Pilar Earthquake Event','Earthquake','Minor structural damage was recorded in older buildings.',3,'2021-04-12',2,4800000.00);

-- Placeholder report metadata demonstrates the relationship; generate a real file in the app before downloading it.
INSERT INTO reports
  (id,report_type,generated_by,generated_at,file_path)
VALUES
  (1,'historical_disaster',1,CURRENT_TIMESTAMP,'storage/reports/sample_historical_disaster_report.pdf');

INSERT INTO audit_logs
  (user_id,action,entity_type,entity_id,metadata,ip_address)
VALUES
  (1,'sample_data_imported','database',NULL,'{"source":"disaster_map_complete.sql"}','127.0.0.1');

COMMIT;

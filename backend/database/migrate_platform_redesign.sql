-- Run against the database selected by the deployment environment, for example:
-- mysql -D disaster_map_demo < migrate_platform_redesign.sql
ALTER TABLE evacuation_centers
  MODIFY status ENUM('open','standby','available','full','closed','under_maintenance','deleted') NOT NULL DEFAULT 'available';
UPDATE evacuation_centers SET status='available' WHERE status IN ('open','standby');
ALTER TABLE evacuation_centers
  MODIFY status ENUM('available','full','closed','under_maintenance','deleted') NOT NULL DEFAULT 'available';

ALTER TABLE evacuation_routes
  ADD COLUMN IF NOT EXISTS distance_km DECIMAL(10,2) NULL AFTER geojson_data,
  ADD COLUMN IF NOT EXISTS estimated_travel_minutes INT UNSIGNED NULL AFTER distance_km,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP;

ALTER TABLE reports MODIFY report_type ENUM('hazard','alert','historical_disaster','evacuation_center') NOT NULL;

CREATE TABLE IF NOT EXISTS notifications (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, user_id BIGINT UNSIGNED NULL, alert_id BIGINT UNSIGNED NULL,
  notification_type ENUM('alert','warning','announcement','system_update') NOT NULL DEFAULT 'alert',
  title VARCHAR(180) NOT NULL, message TEXT NOT NULL, is_read TINYINT(1) NOT NULL DEFAULT 0, read_at TIMESTAMP NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_notification_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_notification_alert FOREIGN KEY (alert_id) REFERENCES alerts(id) ON DELETE CASCADE,
  INDEX idx_notification_delivery (user_id,is_read,created_at)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS weather_updates (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, municipality_id BIGINT UNSIGNED NULL,
  condition_text VARCHAR(120) NOT NULL, temperature_c DECIMAL(5,2) NULL, rainfall_mm DECIMAL(8,2) NULL,
  advisory_level ENUM('normal','advisory','warning','critical') NOT NULL DEFAULT 'normal', source VARCHAR(180) NULL,
  observed_at TIMESTAMP NOT NULL, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_weather_municipality FOREIGN KEY (municipality_id) REFERENCES municipalities(id) ON DELETE CASCADE,
  INDEX idx_weather_scope (municipality_id,observed_at)
) ENGINE=InnoDB;

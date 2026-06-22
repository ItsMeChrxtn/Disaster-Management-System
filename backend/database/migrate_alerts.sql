USE disaster_map;
ALTER TABLE alerts ADD COLUMN alert_type ENUM('weather_alert','flood_alert','earthquake_alert','storm_surge_alert','emergency_alert') NOT NULL DEFAULT 'emergency_alert' AFTER title;
ALTER TABLE alerts MODIFY severity ENUM('info','advisory','warning','severe','critical') NOT NULL;
UPDATE alerts SET severity='warning' WHERE severity='severe';
ALTER TABLE alerts CHANGE severity alert_level ENUM('info','advisory','warning','critical') NOT NULL;
ALTER TABLE alerts MODIFY status ENUM('draft','published','cancelled','sent','deleted') NOT NULL DEFAULT 'draft';
UPDATE alerts SET status='sent' WHERE status='published';
UPDATE alerts SET status='deleted' WHERE status='cancelled';
ALTER TABLE alerts MODIFY status ENUM('draft','sent','deleted') NOT NULL DEFAULT 'draft';
ALTER TABLE alerts CHANGE published_at sent_at TIMESTAMP NULL;
ALTER TABLE alerts DROP FOREIGN KEY fk_alert_hazard;
ALTER TABLE alerts DROP COLUMN hazard_id;
ALTER TABLE alerts DROP COLUMN expires_at;
ALTER TABLE alerts DROP INDEX idx_alert_live, ADD INDEX idx_alert_delivery (status,municipality_id,sent_at);
CREATE TABLE alert_reads (
  alert_id BIGINT UNSIGNED NOT NULL, user_id BIGINT UNSIGNED NOT NULL, read_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (alert_id,user_id), CONSTRAINT fk_alert_read_alert FOREIGN KEY (alert_id) REFERENCES alerts(id) ON DELETE CASCADE,
  CONSTRAINT fk_alert_read_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;


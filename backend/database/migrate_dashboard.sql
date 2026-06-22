USE disaster_map;
CREATE TABLE IF NOT EXISTS safe_zones (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, municipality_id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(180) NOT NULL, address VARCHAR(255) NULL, latitude DECIMAL(10,7) NOT NULL, longitude DECIMAL(10,7) NOT NULL,
  capacity INT UNSIGNED NULL, status ENUM('active','inactive') NOT NULL DEFAULT 'active', created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_safe_zone_municipality FOREIGN KEY (municipality_id) REFERENCES municipalities(id) ON DELETE CASCADE,
  INDEX idx_safe_zone_scope (municipality_id,status)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS evacuation_centers (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, municipality_id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(180) NOT NULL, address VARCHAR(255) NULL, latitude DECIMAL(10,7) NOT NULL, longitude DECIMAL(10,7) NOT NULL,
  capacity INT UNSIGNED NULL, current_occupancy INT UNSIGNED NOT NULL DEFAULT 0, status ENUM('open','closed','standby') NOT NULL DEFAULT 'standby', created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_evacuation_center_municipality FOREIGN KEY (municipality_id) REFERENCES municipalities(id) ON DELETE CASCADE,
  INDEX idx_evacuation_center_scope (municipality_id,status)
) ENGINE=InnoDB;

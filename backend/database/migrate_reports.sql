USE disaster_map;
CREATE TABLE IF NOT EXISTS historical_disasters (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(180) NOT NULL, disaster_type VARCHAR(80) NOT NULL, description TEXT NULL,
  municipality_id BIGINT UNSIGNED NULL, date_occurred DATE NOT NULL,
  casualties INT UNSIGNED NOT NULL DEFAULT 0, damages DECIMAL(15,2) NOT NULL DEFAULT 0,
  CONSTRAINT fk_historical_municipality FOREIGN KEY (municipality_id) REFERENCES municipalities(id) ON DELETE RESTRICT,
  INDEX idx_historical_report (date_occurred,municipality_id,disaster_type)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS reports (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  report_type ENUM('hazard','alert','historical_disaster') NOT NULL,
  generated_by BIGINT UNSIGNED NOT NULL,
  generated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  file_path VARCHAR(500) NOT NULL,
  CONSTRAINT fk_report_user FOREIGN KEY (generated_by) REFERENCES users(id),
  INDEX idx_report_history (generated_by,generated_at,report_type)
) ENGINE=InnoDB;

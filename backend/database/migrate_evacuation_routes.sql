USE disaster_map;
CREATE TABLE IF NOT EXISTS evacuation_routes (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  municipality_id BIGINT UNSIGNED NULL,
  route_name VARCHAR(180) NOT NULL,
  start_location JSON NOT NULL,
  end_location JSON NOT NULL,
  geojson_data JSON NOT NULL,
  CONSTRAINT fk_route_municipality FOREIGN KEY (municipality_id) REFERENCES municipalities(id) ON DELETE SET NULL,
  INDEX idx_route_municipality (municipality_id)
) ENGINE=InnoDB;

-- For databases created with this project's earlier schema.
USE disaster_map;
ALTER TABLE municipalities CHANGE name municipality_name VARCHAR(120) NOT NULL;
ALTER TABLE municipalities ADD COLUMN description TEXT NULL AFTER municipality_name;
ALTER TABLE municipalities ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER created_at;
ALTER TABLE municipalities DROP INDEX uq_municipality;
ALTER TABLE municipalities DROP COLUMN province;
ALTER TABLE municipalities DROP COLUMN boundary_geojson;
ALTER TABLE municipalities ADD UNIQUE KEY uq_municipality_name (municipality_name);

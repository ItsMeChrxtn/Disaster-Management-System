USE disaster_map;
ALTER TABLE hazards CHANGE name hazard_name VARCHAR(180) NOT NULL;
ALTER TABLE hazards MODIFY type VARCHAR(50) NOT NULL;
UPDATE hazards SET type=CASE
  WHEN type='flood' THEN 'flood_zone'
  WHEN type='storm_surge' THEN 'storm_surge_area'
  WHEN type='earthquake' THEN 'earthquake_area'
  ELSE 'high_risk_area' END;
ALTER TABLE hazards CHANGE type hazard_type VARCHAR(80) NOT NULL;
ALTER TABLE hazards CHANGE severity risk_level ENUM('low','moderate','high','critical') NOT NULL;
ALTER TABLE hazards CHANGE geojson geojson_data JSON NOT NULL;
ALTER TABLE hazards DROP COLUMN instructions;
ALTER TABLE hazards DROP INDEX idx_hazard_map, ADD INDEX idx_hazard_map (status,hazard_type,risk_level,municipality_id);
ALTER TABLE hazards ADD FULLTEXT KEY idx_hazard_search (hazard_name,description);

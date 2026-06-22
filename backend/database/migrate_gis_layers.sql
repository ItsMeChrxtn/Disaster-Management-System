USE disaster_map;

-- Existing routes remain province-wide until assigned during a later edit.
ALTER TABLE evacuation_routes ADD COLUMN municipality_id BIGINT UNSIGNED NULL AFTER id;
ALTER TABLE evacuation_routes ADD INDEX idx_route_municipality (municipality_id);
ALTER TABLE evacuation_routes ADD CONSTRAINT fk_route_municipality FOREIGN KEY (municipality_id) REFERENCES municipalities(id) ON DELETE SET NULL;

USE disaster_map;

-- Upgrades the earlier reporting-only table while preserving impact data.
ALTER TABLE historical_disasters CHANGE disaster_name title VARCHAR(180) NOT NULL;
UPDATE historical_disasters
SET description=CONCAT_WS('\n',NULLIF(description,''),CONCAT('Legacy severity: ',severity),CONCAT('Legacy affected count: ',affected_count));
ALTER TABLE historical_disasters
  CHANGE event_date date_occurred DATE NOT NULL,
  CHANGE fatalities casualties INT UNSIGNED NOT NULL DEFAULT 0,
  CHANGE estimated_damage damages DECIMAL(15,2) NOT NULL DEFAULT 0,
  MODIFY municipality_id BIGINT UNSIGNED NULL,
  DROP COLUMN severity,
  DROP COLUMN affected_count,
  DROP COLUMN created_at;
ALTER TABLE historical_disasters DROP FOREIGN KEY fk_historical_municipality;
ALTER TABLE historical_disasters
  ADD CONSTRAINT fk_historical_municipality FOREIGN KEY (municipality_id) REFERENCES municipalities(id) ON DELETE RESTRICT;

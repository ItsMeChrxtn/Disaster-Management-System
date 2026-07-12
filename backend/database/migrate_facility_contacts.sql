ALTER TABLE safe_zones
  ADD COLUMN IF NOT EXISTS contact_person VARCHAR(120) NULL AFTER capacity;

ALTER TABLE safe_zones
  ADD COLUMN IF NOT EXISTS contact_number VARCHAR(30) NULL AFTER contact_person;

ALTER TABLE evacuation_centers
  ADD COLUMN IF NOT EXISTS contact_person VARCHAR(120) NULL AFTER address;

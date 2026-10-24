-- Oct 2026 revision: barangay tagging for hazards and safe-zone perimeters.
-- The API also adds these columns automatically on first use (App\Core\Schema),
-- so running this file manually is optional. Safe to re-run on MariaDB.
ALTER TABLE hazards ADD COLUMN IF NOT EXISTS barangays TEXT NULL AFTER municipality_id;
ALTER TABLE safe_zones ADD COLUMN IF NOT EXISTS perimeter_radius_m INT UNSIGNED NULL AFTER capacity;

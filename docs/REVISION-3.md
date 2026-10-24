# Revision 3 (October 2026)

Changes made for the third instructor revision (`3rd-REVISION-10-22-2026.pdf`) and the
PDRRMO data files (evacuation-center list, typhoon summary 2021-2025, flood/landslide
incidents 2021-2026, earthquake sheet).

## Web

| Item | Where |
| --- | --- |
| Multi-hazard status and Rainfall watch are collapsible dropdowns (summary chips when closed, state remembered) | `admin/views/overview.html`, `initCollapsiblePanels()` in `dashboard.js` |
| Dashboard alerts and stat cards are clickable (alert detail dialog, card opens its module) | `alertMarkup()` / `showAlertDetail()` in `dashboard.js` |
| Residents no longer see CSV / Excel / PDF / Print export buttons | `canExport` in `ui.js`; `manager-only` on the safe-zone toolbar |
| Historical records show affected barangays (list and count), injured, evacuated families, event and source, with a summary strip | `admin/views/history.html`, `renderHistoricalDisasters()` |
| Reports: the Generate button now works (the handler looked for a `type="submit"` button that did not exist) and the file downloads right away | `reportForm` submit handler |
| New module: PDRRMO and MDRRMO/CDRRMO coordination channel | `admin/views/coordination.html`, `assets/js/coordination.js` |
| Province zoom shows facility pins as dots (about 700 evacuation centers) | `CaviteGIS.compactFacilities()` |

The municipal role (`subadmin`) is the MDRRMO/CDRRMO office: CDRRMO for cities and MDRRMO for
municipalities. It now has a **Municipality** menu item for the channel. The admin (PDRRMO)
uses it from **Municipalities → Coordination channel** or the **LGU coordination** menu item.
The PDRRMO can broadcast to all LGUs or to selected ones and can require an acknowledgement.
LGUs send situation reports and requests back. Both sides get bell and mobile notifications.

## API

- `GET /api/coordination/channels`, `GET|POST /api/coordination/messages`,
  `POST /api/coordination/messages/{id}/acknowledge` (municipal officer only).
- `historical-disasters` accepts `event_name`, `injured`, `evacuated_families`,
  `affected_barangays` (one per line), `affected_barangay_count` and `source`.
  `municipality_id` may be empty for a province-wide record.
- Residents now receive province-wide safe-zone and evacuation-center lists (they were limited
  to their own municipality, which left the mobile directory empty).
- The notification feed carries `kind`, `alert_level`, `alert_type` and `municipality_name`.

New tables and columns create themselves on first use (`Schema::ensureTable` /
`ensureColumn`). `database/migrate_revision3_coordination.sql` is the manual fallback.

## Data import

`database/seed_pdrrmo_revision3.php` imports `database/data/pdrrmo_*.txt`:

- 698 evacuation centers. 513 use the listed coordinates. 175 sit at their barangay center
  because the list had no coordinates, a repeated placeholder pair, or a point outside the
  town. 10 Tagaytay entries sit at the town center because those barangays were renamed.
  The address says when a pin is approximate. Capacity is not in the source, so it shows as
  "Not specified".
- 164 historical records: each typhoon, flood, landslide or earthquake record per
  municipality, with the affected barangays.

Run `php database/seed_pdrrmo_revision3.php --sql database/seed_pdrrmo_revision3.sql` to
regenerate the SQL file. Import that file in phpMyAdmin on the live database. It is safe to
run more than once.

## Mobile (APK 1.5.0)

- Push notifications also arrive while the app is closed: Android WorkManager checks about
  every 15 minutes (the Android minimum), and the app polls every 30 seconds while open. This
  covers alerts, PDRRMO messages and LGU reports for every role. Instant server push would
  need a Firebase (FCM) project.
- The dashboard has tappable cards and alerts plus the two dropdown panels. The landing
  screen layout was fixed.
- Facilities: the map opens on all of Cavite, the legend uses the pin icons, the web's
  explainer cards were added, the directory loads in pages, and residents cannot export.
- The public map's layer list and pins use an icon per layer instead of color dots.
- New Municipality / LGU coordination screen. Historical records show barangays, injured and
  evacuated families.

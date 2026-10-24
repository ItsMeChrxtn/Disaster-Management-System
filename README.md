# Disaster Map

A web-based hazard mapping and near-real-time alert system for provincial and municipal DRRM offices and residents.

The reviewed folder structure, full API contract, database relationships, authentication flow, role matrix, and production deployment guidance are documented in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

The repository includes the compiled Tailwind stylesheet, so PHP/Apache is the only local application runtime. No Node.js server, Bootstrap, React, or frontend framework is used. Leaflet 1.9.4 is self-hosted under `frontend/vendor/leaflet`; SweetAlert2 is loaded by the static pages.

## Structure

```text
backend/
  app/Core/           HTTP, routing, validation, database
  app/Controllers/    REST controllers
  app/Middleware/     authentication and role authorization
  app/Models/          domain persistence
  database/           MySQL schema and admin seed command
  public/             Apache web root (the only backend folder that is web-exposed)
  routes/             API route definitions
frontend/
  assets/css/         responsive presentation
  assets/js/          API, SweetAlert, modal, table, auth, dashboard, and map helpers
  index.html           public Leaflet hazard map
  login.html           resident and staff authentication
  dashboard.html       role-aware operational dashboard
```

## Android app

A Flutter mobile app with the same features as the website lives in `mobile/` (see `mobile/README.md`). The signed APK is published at `frontend/downloads/disaster-map.apk` and linked from the landing page (`#mobile-app`), the hero, the footer, and the login page. `frontend/.htaccess` adds the `application/vnd.android.package-archive` MIME type so Apache serves it as a download. Rebuild with `flutter build apk --release --target-platform android-arm,android-arm64` and copy the APK into `frontend/downloads/` before deploying.

## Local setup

1. For a demo installation with sample data, import `backend/database/disaster_map_complete.sql`. For an empty installation, import `backend/database/schema.sql`.
2. Copy `backend/.env.example` to `backend/.env`, update database/CORS values, and set a random `JWT_SECRET` of at least 32 characters.
3. Empty installations can create an admin with `php backend/database/seed.php admin@example.gov.ph StrongPasswordHere`. Demo accounts use `ChangeMe123!` and must be changed immediately.
4. With XAMPP, keep this repository under `C:\xampp\htdocs\Disaster-Management-System`, start Apache and MySQL, then open `http://localhost/Disaster-Management-System/frontend/`.
5. Set `frontend/config.js` to `http://localhost/Disaster-Management-System/backend/public/api` for the XAMPP API path. The supplied configuration can also point to a separate PHP development server.
6. Existing databases must run `backend/database/migrate_platform_redesign.sql` against the configured database after the earlier module migrations. For this repository's local demo database: `C:\xampp\mysql\bin\mysql.exe -u root -D disaster_map_demo < backend\database\migrate_platform_redesign.sql`. The migration intentionally does not hard-code a database name.

## UI architecture

- `assets/css/theme.css` is the single design system stylesheet (Inter, blue/navy palette, buttons, pills, tables, modals, Leaflet and SweetAlert2 theming, public landing, auth pages, dashboard). It loads after the compiled Tailwind utilities and intentionally uses no `!important` except for `.hidden`; `npm run build:css` recompiles `tailwind.css` from the HTML (including `admin/views/*.html`) and JS sources.
- `assets/js/alerts.js` is the only notification/confirmation interface. CRUD success, API errors, authentication, destructive actions, alert sending, and report generation use SweetAlert2; native browser dialogs are not used.
- `assets/js/modal.js` upgrades the live user, municipality, hazard, safe-zone, center, route, alert, historical-record, and report forms into responsive modal dialogs. It preserves each existing submit handler and API contract.
- `assets/js/table.js` supplies module filters while the shared table controller supplies search, sorting, pagination, CSV, Excel-compatible export, print, and PDF-through-print output.
- `assets/js/ui.js` owns the role-aware navigation shell, breadcrumbs, dark mode, profile menu, global search, and notification dropdown.
- Admin data remains province-wide. Sub Admin queries and writes are forced to the assigned municipality by backend middleware/controllers. Residents receive read-only operational data and municipality-targeted alerts.

## Environment variables

Configure these in `backend/.env` (create it on the server; it is never committed): `APP_ENV`, `APP_DEBUG`, `APP_URL`, `FRONTEND_URL`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`, `JWT_SECRET`, `JWT_TTL`, and optional `WEATHER_API_URL`. On a single-domain Hostinger deployment `APP_URL` and `FRONTEND_URL` are normally the same origin (e.g. `https://yourdomain.com`); `FRONTEND_URL` accepts a comma-separated allowlist if you also need to allow a staging origin.

## Hostinger deployment (single hosting account)

This app is designed to run entirely from one Apache + PHP + MySQL hosting account — no separate frontend/backend host is required.

1. **Upload the repository** to the domain's document root (e.g. `public_html`), keeping the existing layout: root `index.php`, `frontend/`, `backend/`. `backend/vendor/` and `backend/.env` are gitignored, so upload them separately (FTP/File Manager), or run `composer install --no-dev --optimize-autoloader` from an SSH terminal if your plan includes one.
2. **Create the MySQL database** in hPanel → Databases → MySQL Databases (Hostinger prefixes the name/user, e.g. `u123456789_disaster_map`), then import your schema/data through phpMyAdmin. Use `backend/database/schema.sql` for an empty install, `backend/database/disaster_map_complete.sql` for schema + demo data, or a `mysqldump` export of an existing database — strip any `CREATE DATABASE`/`USE` statements first since shared hosting accounts cannot create databases via SQL.
3. **Create `backend/.env`** from `backend/.env.example` with the Hostinger DB credentials, `DB_HOST=localhost`, and `APP_URL`/`FRONTEND_URL` set to your Hostinger domain.
4. **Confirm `mod_rewrite` and `.htaccess` overrides are enabled** (default on Hostinger). `backend/.htaccess` denies direct access to everything in `backend/` except `backend/public/` — verify `backend/.env`, `backend/composer.json`, and anything under `backend/database/` return 403 when requested directly by URL.
5. **Set folder permissions** so PHP can write to `backend/storage/reports` (typically 755; Hostinger's filesystem is persistent, so generated PDF/Excel reports do not need external object storage).
6. Visit `https://yourdomain.com/` — it redirects to `frontend/`; `frontend/config.js` derives the API base URL from the current origin automatically, so no hardcoded API URL is needed as long as `frontend/` and `backend/` stay siblings under the same domain.

## API

All responses use `{ "success": boolean, "data": ... }`; errors include `message` and optional field `errors`.

| Method | Route | Access |
|---|---|---|
| POST | `/api/auth/register`, `/api/auth/login` | Public |
| POST | `/api/auth/login/admin`, `/login/subadmin`, `/login/resident` | Public, role-specific |
| POST | `/api/auth/forgot-password`, `/api/auth/reset-password` | Public |
| GET | `/api/auth/me` | Authenticated |
| POST | `/api/auth/logout` | Authenticated |
| PUT | `/api/auth/profile`, `/api/auth/change-password` | Authenticated |
| GET | `/api/hazards`, `/api/alerts` | Public |
| GET | `/api/hazards`, `/api/hazards/{id}` | Public; supports search and filters |
| POST/PUT/DELETE | `/api/hazards[/{id}]` | Admin |
| GET | `/api/alerts` | Public sent alerts |
| GET | `/api/alerts/manage` | Admin and scoped Sub Admin |
| POST/PUT/DELETE | `/api/alerts[/{id}]` | Admin and scoped Sub Admin |
| POST | `/api/alerts/{id}/send` | Admin and scoped Sub Admin |
| GET | `/api/notifications/history`, `/unread-count` | Authenticated resident delivery |
| POST | `/api/notifications/{id}/read` | Authenticated read receipt |
| GET | `/api/weather/current` | Authenticated current conditions and derived advisories |
| GET/POST | `/api/reports` | Admin and Sub Admin report history/generation |
| GET | `/api/reports/{id}/download` | Authorized PDF or Excel download |
| DELETE | `/api/reports/{id}` | Authorized generated-file deletion |
| GET | `/api/historical-disasters` | Authenticated historical record listing and filters |
| GET | `/api/historical-disasters/{id}` | Authenticated historical record details |
| POST/PUT/DELETE | `/api/historical-disasters[/{id}]` | Admin historical disaster CRUD |
| GET | `/api/gis/layers?municipality_id={id}` | Public GIS layers and municipality filtering |
| GET/POST | `/api/reports` | Admin and Sub Admin report history/generation |
| GET | `/api/reports/{id}/download` | Protected PDF/XLSX download |
| GET | `/api/admin/stats`, `/api/admin/users` | Admin, Sub Admin |
| POST | `/api/admin/users` | Admin |
| GET | `/api/dashboard` | Authenticated; cards and charts are role-scoped |
| GET/POST | `/api/municipalities` | Admin |
| GET/PUT/DELETE | `/api/municipalities/{id}` | Admin |
| GET | `/api/municipalities/options` | Public active-municipality options |
| GET | `/api/users`, `/api/users/{id}` | Admin; Sub Admin is limited to municipal residents |
| POST/PUT/DELETE | `/api/users[/{id}]` | Admin |
| PUT | `/api/users/{id}/disable`, `/activate` | Admin |
| GET | `/api/safe-zones`, `/api/safe-zones/{id}` | Authenticated |
| GET | `/api/safe-zones/nearest?latitude=&longitude=` | Authenticated |
| POST/PUT/DELETE | `/api/safe-zones[/{id}]` | Admin and scoped Sub Admin |
| GET | `/api/evacuation-centers`, `/api/evacuation-centers/{id}` | Authenticated |
| GET | `/api/evacuation-centers/nearest?latitude=&longitude=` | Authenticated |
| POST/PUT/DELETE | `/api/evacuation-centers[/{id}]` | Admin and scoped Sub Admin |
| GET | `/api/evacuation-routes`, `/api/evacuation-routes/{id}` | Authenticated |
| GET | `/api/evacuation-routes/nearest-destination`, `/road` | Authenticated route planning |
| POST/PUT/DELETE | `/api/evacuation-routes[/{id}]` | Admin and Sub Admin |

Sub Admin writes are forced to their assigned municipality. Residents have read-only operational access. When upgrading an existing installation, run `backend/database/migrate_auth_v2.sql` once instead of recreating the database.

The dashboard uses `safe_zones` and `evacuation_centers`; existing installations should run `backend/database/migrate_dashboard.sql`. Resident nearby counts use a 20 km radius when geolocation permission is granted and otherwise use municipal scope. Weather is read from Open-Meteo using the resident location or municipality center.

Municipality management uses soft deletion to preserve dependent records. Existing databases created from the earlier project schema should run `backend/database/migrate_municipalities.sql` once.

User deletion is also soft (`status = deleted`); disabling and deletion revoke all JWT sessions immediately. Run `backend/database/migrate_users.sql` when upgrading an earlier schema.

Hazards accept GeoJSON geometry, Feature, FeatureCollection, and GeometryCollection payloads up to 2 MB. Public filters use `hazard_type`, `risk_level`, `municipality_id`, and `search`. Run `backend/database/migrate_hazards.sql` when upgrading an earlier schema.

Safe Zone deletion is soft and Sub Admin writes are always forced to the assigned municipality. Nearest results use great-circle distance and return up to 20 active zones. Run `backend/database/migrate_safe_zones.sql` when upgrading.

Evacuation centers separate operational `open`, `standby`, and `closed` states from soft deletion. Nearest results include open and standby centers. Run `backend/database/migrate_evacuation_centers.sql` when upgrading.

Evacuation route planning uses OpenStreetMap tiles and OSRM road geometry. If road routing is unavailable, the API returns a clearly identified straight-line fallback. Stored routes use GeoJSON LineString data. Run `backend/database/migrate_evacuation_routes.sql` when upgrading.

Alerts use a draft → sent lifecycle with soft deletion. Residents receive province-wide and matching-municipality alerts through polling, optional browser notifications, history, unread counts, and read receipts. Run `backend/database/migrate_alerts.sql` when upgrading.

Weather monitoring uses Open-Meteo current and hourly forecast data. Rainfall, thunderstorm, and strong-wind levels are derived guidance rather than official warnings; PAGASA and DRRMO bulletins remain authoritative.

Reporting generates Hazard, Alert, and Historical Disaster reports as PDF or Excel. PDF reports use Dompdf; Excel workbooks use PhpSpreadsheet. Run `backend/database/migrate_reports.sql` when upgrading. `backend/storage/reports` must be writable by PHP; on Hostinger this is regular persistent disk storage, so no object-storage replacement is needed.

Reports use Dompdf and PhpSpreadsheet to produce real PDF and XLSX files. Admin reports cover all municipalities; Sub Admin reports are municipality-scoped and only their own generated files are listed. Run `backend/database/migrate_reports.sql` when upgrading. Downloads are always served through the authenticated `/api/reports/{id}/download` endpoint, never as direct static links.

Historical disaster records are readable by every authenticated role and writable only by Admin. Existing installations that used the earlier reporting-only historical table must run `backend/database/migrate_historical_disasters.sql` once before deploying this module.

The public GIS map combines flood, storm surge, earthquake, safe-zone, evacuation-center, and route layers. Existing installations must run `backend/database/migrate_gis_layers.sql` once to add municipality scoping to evacuation routes.

## Deployment

See [Hostinger deployment](#hostinger-deployment-single-hosting-account) above for the primary deployment path. In short: one Apache + PHP + MySQL hosting account serves both `frontend/` and `backend/` from the same domain, so no CORS configuration or cross-host API URL is required.

## Security baseline

- Passwords use PHP `password_hash`. Access tokens are signed HS256 JWTs with issuer, subject, role, issued-at, expiry, and random session ID claims.
- Every JWT session ID is checked against `user_sessions`; logout, password reset, account suspension, expiry, and explicit revocation invalidate access.
- Forgot-password tokens are random, stored only as SHA-256 hashes, expire after 30 minutes by default, and are single-use. Production must connect token delivery to its transactional email/SMS provider; debug mode returns the token for local testing.
- PDO native prepared statements prevent SQL injection. JSON is safely encoded and map popup content is escaped.
- CORS uses an allowlist; security headers are included. Production errors do not expose traces.
- `backend/.htaccess` denies direct web access to everything in `backend/` except `backend/public/`. This matters most on shared hosting where `frontend/` and `backend/` sit under the same document root — without it, `.env`, `vendor/`, `database/*.sql`, and app source would be directly downloadable by URL.
- Municipal scoping is enforced server-side, not trusted to the UI.
- Serve only over HTTPS. Use secret environment variables, least-privilege DB credentials, regular backups, rate limiting at the edge, and scheduled deletion of expired tokens.
- For high-volume emergency delivery, connect alert creation to an SMS/push provider through a queue. Browser polling currently refreshes public alerts every 30 seconds.

## Production improvements

Compile and self-host Tailwind instead of using its CDN, add email/phone verification, record audit logs in each mutating controller, validate GeoJSON geometry/size more strictly, add pagination, automated integration tests, Redis-backed throttling, and a queued notification worker.

# Disaster Map Production Architecture

This document describes the implemented PHP 8+, MySQL, Tailwind CSS, JavaScript, Leaflet, and OpenStreetMap application. The backend follows a lightweight MVC structure: routes dispatch to controllers, controllers validate and authorize requests, models own persistence, and services handle non-CRUD domain work.

## 1. Complete folder structure

```text
Disaster-Management-System/
├── backend/
│   ├── app/
│   │   ├── Controllers/
│   │   │   ├── AdminController.php
│   │   │   ├── AlertController.php
│   │   │   ├── AuthController.php
│   │   │   ├── DashboardController.php
│   │   │   ├── EvacuationCenterController.php
│   │   │   ├── EvacuationRouteController.php
│   │   │   ├── GisController.php
│   │   │   ├── HazardController.php
│   │   │   ├── HistoricalDisasterController.php
│   │   │   ├── MunicipalityController.php
│   │   │   ├── ReportController.php
│   │   │   ├── SafeZoneController.php
│   │   │   ├── UserController.php
│   │   │   └── WeatherController.php
│   │   ├── Core/
│   │   │   ├── Database.php
│   │   │   ├── Jwt.php
│   │   │   ├── Request.php
│   │   │   ├── Response.php
│   │   │   ├── Router.php
│   │   │   └── Validator.php
│   │   ├── Middleware/
│   │   │   ├── AuthMiddleware.php
│   │   │   └── RoleMiddleware.php
│   │   ├── Models/
│   │   │   ├── Alert.php
│   │   │   ├── BaseModel.php
│   │   │   ├── EvacuationCenter.php
│   │   │   ├── EvacuationRoute.php
│   │   │   ├── Hazard.php
│   │   │   ├── HistoricalDisaster.php
│   │   │   ├── Municipality.php
│   │   │   ├── Report.php
│   │   │   ├── SafeZone.php
│   │   │   └── User.php
│   │   └── Services/
│   │       └── ReportGenerator.php
│   ├── database/
│   │   ├── disaster_map_complete.sql
│   │   ├── schema.sql
│   │   ├── seed.php
│   │   └── migrate_*.sql
│   ├── public/
│   │   └── index.php
│   ├── routes/
│   │   └── api.php
│   ├── storage/
│   │   └── reports/
│   ├── vendor/                 # Composer-generated dependencies
│   ├── .env.example
│   ├── bootstrap.php
│   ├── composer.json
│   ├── composer.lock
│   └── railway.json
├── frontend/
│   ├── assets/
│   │   ├── css/app.css
│   │   └── js/
│   │       ├── api.js
│   │       ├── auth.js
│   │       ├── dashboard.js
│   │       └── map.js
│   ├── dashboard.html
│   ├── forgot-password.html
│   ├── index.html
│   ├── login.html
│   ├── register.html
│   ├── reset-password.html
│   ├── config.example.js
│   ├── config.js
│   └── vercel.json
├── docs/
│   └── ARCHITECTURE.md
└── README.md
```

`backend/public` is the only web-accessible backend directory. Application classes, environment files, generated reports, database scripts, and Composer internals must not be served directly.

## 2. Complete API routes

All JSON responses use `{ "success": true, "data": ... }`. Errors use `{ "success": false, "message": "...", "errors": {...} }`.

### Public routes

| Method | Route | Purpose |
|---|---|---|
| GET | `/api/health` | Service health check |
| GET | `/api/gis/layers?municipality_id={id}` | Sanitized GIS layers and municipality options |
| POST | `/api/auth/register` | Resident registration |
| POST | `/api/auth/login` | Generic login |
| POST | `/api/auth/login/admin` | Admin-only login endpoint |
| POST | `/api/auth/login/subadmin` | Sub Admin-only login endpoint |
| POST | `/api/auth/login/resident` | Resident-only login endpoint |
| POST | `/api/auth/forgot-password` | Request a password-reset token |
| POST | `/api/auth/reset-password` | Consume a password-reset token |
| GET | `/api/municipalities/options` | Active municipality selector options |
| GET | `/api/hazards` | Active hazards; supports type, risk, municipality, and search filters |
| GET | `/api/hazards/{id}` | Active hazard details |
| GET | `/api/alerts` | Sent public alerts |

### Authenticated account and dashboard routes

| Method | Route | Roles |
|---|---|---|
| GET | `/api/auth/me` | All authenticated roles |
| POST | `/api/auth/logout` | All authenticated roles |
| PUT | `/api/auth/profile` | All authenticated roles |
| PUT | `/api/auth/change-password` | All authenticated roles |
| GET | `/api/dashboard` | All authenticated roles; response is role-aware |
| GET | `/api/weather/current` | All authenticated roles |

### Municipality routes

| Method | Route | Roles |
|---|---|---|
| GET | `/api/municipalities` | Admin |
| POST | `/api/municipalities` | Admin |
| GET | `/api/municipalities/{id}` | Admin |
| PUT | `/api/municipalities/{id}` | Admin |
| DELETE | `/api/municipalities/{id}` | Admin; deactivates record |

### User routes

| Method | Route | Roles |
|---|---|---|
| GET | `/api/users` | Admin |
| POST | `/api/users` | Admin |
| GET | `/api/users/{id}` | Admin |
| PUT | `/api/users/{id}` | Admin |
| DELETE | `/api/users/{id}` | Admin; soft deletes account |
| PUT | `/api/users/{id}/disable` | Admin |
| PUT | `/api/users/{id}/activate` | Admin |

### Hazard routes

| Method | Route | Roles and scope |
|---|---|---|
| POST | `/api/hazards` | Admin: any municipality; Sub Admin: assigned municipality |
| PUT | `/api/hazards/{id}` | Admin: any; Sub Admin: assigned municipality only |
| DELETE | `/api/hazards/{id}` | Admin: any; Sub Admin: assigned municipality only; archives record |

### Safe-zone routes

| Method | Route | Roles and scope |
|---|---|---|
| GET | `/api/safe-zones` | All authenticated; Sub Admin list is municipality-scoped |
| GET | `/api/safe-zones/nearest` | All authenticated |
| GET | `/api/safe-zones/{id}` | All authenticated; Sub Admin scope enforced |
| POST | `/api/safe-zones` | Admin and Sub Admin; Sub Admin municipality forced server-side |
| PUT | `/api/safe-zones/{id}` | Admin and scoped Sub Admin |
| DELETE | `/api/safe-zones/{id}` | Admin and scoped Sub Admin; deactivates record |

### Evacuation-center routes

| Method | Route | Roles and scope |
|---|---|---|
| GET | `/api/evacuation-centers` | All authenticated; Sub Admin list is municipality-scoped |
| GET | `/api/evacuation-centers/nearest` | All authenticated |
| GET | `/api/evacuation-centers/{id}` | All authenticated; Sub Admin scope enforced |
| POST | `/api/evacuation-centers` | Admin and Sub Admin; Sub Admin municipality forced server-side |
| PUT | `/api/evacuation-centers/{id}` | Admin and scoped Sub Admin |
| DELETE | `/api/evacuation-centers/{id}` | Admin and scoped Sub Admin; soft deletes record |

### Evacuation-route routes

| Method | Route | Roles and scope |
|---|---|---|
| GET | `/api/evacuation-routes` | All authenticated; Sub Admin list is municipality-scoped |
| GET | `/api/evacuation-routes/nearest-destination` | All authenticated |
| GET | `/api/evacuation-routes/road` | All authenticated; OSRM route with straight-line fallback |
| GET | `/api/evacuation-routes/{id}` | All authenticated; Sub Admin scope enforced |
| POST | `/api/evacuation-routes` | Admin and Sub Admin |
| PUT | `/api/evacuation-routes/{id}` | Admin and scoped Sub Admin |
| DELETE | `/api/evacuation-routes/{id}` | Admin and scoped Sub Admin |

### Alert and notification routes

| Method | Route | Roles and scope |
|---|---|---|
| GET | `/api/alerts/manage` | Admin: all; Sub Admin: assigned municipality |
| GET | `/api/alerts/{id}` | Admin and scoped Sub Admin |
| POST | `/api/alerts` | Admin and Sub Admin; Sub Admin municipality forced server-side |
| PUT | `/api/alerts/{id}` | Admin and scoped Sub Admin |
| DELETE | `/api/alerts/{id}` | Admin and scoped Sub Admin; soft deletes alert |
| POST | `/api/alerts/{id}/send` | Admin and scoped Sub Admin |
| GET | `/api/notifications/history` | All authenticated; resident municipality plus province-wide alerts |
| GET | `/api/notifications/unread-count` | All authenticated |
| POST | `/api/notifications/{id}/read` | All authenticated, only if alert is available to user |

### Historical-record routes

| Method | Route | Roles |
|---|---|---|
| GET | `/api/historical-disasters` | Admin and Resident |
| GET | `/api/historical-disasters/{id}` | Admin and Resident |
| POST | `/api/historical-disasters` | Admin |
| PUT | `/api/historical-disasters/{id}` | Admin |
| DELETE | `/api/historical-disasters/{id}` | Admin |

### Report routes

| Method | Route | Roles and scope |
|---|---|---|
| GET | `/api/reports` | Admin: all report metadata; Sub Admin: own reports |
| POST | `/api/reports` | Admin: optional municipality; Sub Admin: assigned municipality |
| GET | `/api/reports/{id}/download` | Admin or owning Sub Admin |
| DELETE | `/api/reports/{id}` | Admin or owning Sub Admin |

### Administrative statistics

| Method | Route | Roles |
|---|---|---|
| GET | `/api/admin/stats` | Admin and Sub Admin; response is municipality-scoped for Sub Admin |

## 3. Database relationships

The complete schema is in `backend/database/disaster_map_complete.sql`.

| Parent | Child | Cardinality | Foreign key | Delete behavior |
|---|---|---:|---|---|
| municipalities | users | 1:N | `users.municipality_id` | SET NULL |
| municipalities | hazards | 1:N | `hazards.municipality_id` | SET NULL |
| municipalities | safe_zones | 1:N | `safe_zones.municipality_id` | CASCADE |
| municipalities | evacuation_centers | 1:N | `evacuation_centers.municipality_id` | CASCADE |
| municipalities | evacuation_routes | 1:N | `evacuation_routes.municipality_id` | SET NULL |
| municipalities | alerts | 1:N | `alerts.municipality_id` | SET NULL |
| municipalities | historical_disasters | 1:N | `historical_disasters.municipality_id` | RESTRICT |
| users | user_sessions | 1:N | `user_sessions.user_id` | CASCADE |
| users | password_reset_tokens | 1:N | `password_reset_tokens.user_id` | CASCADE |
| users | hazards | 1:N | `hazards.created_by` | RESTRICT |
| users | alerts | 1:N | `alerts.created_by` | RESTRICT |
| users | reports | 1:N | `reports.generated_by` | RESTRICT |
| users | audit_logs | 1:N | `audit_logs.user_id` | SET NULL |
| users | alert_reads | 1:N | `alert_reads.user_id` | CASCADE |
| alerts | alert_reads | 1:N | `alert_reads.alert_id` | CASCADE |

`alert_reads` implements a many-to-many user/alert read-state relationship. Province-wide hazards, routes, alerts, and legacy historical records may have a null municipality. New municipality-managed records are assigned server-side for Sub Admin requests.

Important indexes include:

- `users(municipality_id, role, status)` for scoped resident management and dashboard counts.
- `hazards(status, hazard_type, risk_level, municipality_id)` plus full-text hazard search.
- Facility municipality/status and latitude/longitude indexes for filtering and proximity candidates.
- `alerts(status, municipality_id, sent_at)` for delivery/history queries.
- `historical_disasters(date_occurred, municipality_id, disaster_type)` plus full-text search.
- Session and reset-token validation indexes for authentication hot paths.
- Report generator/date indexes and audit entity/user indexes.

## 4. Authentication flow

```text
Registration or Login
        |
        v
Validate body, account status, role endpoint, password_hash/password_verify
        |
        v
Create random 32-character JTI and user_sessions row with expiry
        |
        v
Sign HS256 JWT: iss + sub(user id) + jti + role + iat + exp
        |
        v
Browser stores token in sessionStorage and sends Authorization: Bearer <JWT>
        |
        v
AuthMiddleware verifies signature, issuer, expiry, active session, and active user
        |
        v
RoleMiddleware checks route-level role; controller checks municipality ownership
        |
        v
Controller validates input, executes model/service, returns JSON
```

Logout revokes the current JTI in `user_sessions`. Password resets hash the one-time token with SHA-256, enforce expiry/one-time use, update the password using PHP's password API, and revoke active sessions. Password changes revoke the user's other sessions. Disabled or deleted users fail session validation immediately.

Production authentication requirements:

- Use a random `JWT_SECRET` of at least 32 characters and rotate it through Railway secrets.
- Serve API and frontend only over HTTPS.
- Restrict `FRONTEND_URL` to explicit Vercel origins; never use wildcard credentialed CORS.
- Keep access tokens short-lived. For higher-risk deployments, migrate browser token storage from `sessionStorage` to Secure, HttpOnly, SameSite cookies with CSRF protection.
- Add rate limiting to login, registration, forgot-password, reset-password, geocoding, and routing endpoints at the edge or API layer.
- Connect a transactional email provider; debug reset tokens must remain disabled in production.

## 5. Role permissions

| Module/action | Admin (PDRRMO) | Sub Admin (MDRRMO) | Resident |
|---|---|---|---|
| Dashboard and weather | Province-wide | Assigned municipality | Personal/local view |
| Municipalities | Full CRUD/deactivate | No access | Public options only |
| Users | Full CRUD/status control | No access | Own profile/password |
| Hazard map | View all | View assigned municipality | View public GIS map |
| Hazard management | Full CRUD/archive | CRUD/archive in assigned municipality | No writes |
| Safe zones | Full CRUD | CRUD in assigned municipality | View and nearest search |
| Evacuation centers | Full CRUD | CRUD in assigned municipality | View and nearest search |
| Routes | Full CRUD | CRUD in assigned municipality | View and route planning |
| Alerts | Full lifecycle and province-wide targeting | Full lifecycle in assigned municipality | Receive, view history, mark read |
| Reports | Generate/view/download all | Generate municipality-scoped reports; own history/files | No generated-file access |
| Historical records | Full CRUD | No direct record access | Read/search historical records |
| Profile/password/logout | Own account | Own account | Own account |

Frontend visibility is only a usability layer. Every privileged route is protected independently by authentication, role middleware, and—for MDRRMO resources—controller-level municipality ownership checks.

## Production deployment structure

```text
Vercel (HTTPS)
  └── frontend/* static HTML/CSS/JS
          |
          | HTTPS JSON + Bearer JWT
          v
Railway PHP service
  └── backend/public/index.php -> Router -> Middleware -> Controller -> Model/Service
          |                                      |
          | PDO prepared statements              ├── Open-Meteo
          |                                      ├── OSRM
          v                                      └── persistent report storage
Railway MySQL
```

Before production launch:

1. Import `schema.sql` for an empty database, or `disaster_map_complete.sql` only for a disposable demo environment.
2. Set production environment secrets and disable `APP_DEBUG`.
3. Replace local `backend/storage/reports` persistence with Railway volume storage or S3-compatible object storage.
4. Run Composer with `--no-dev --optimize-autoloader` and pin PHP 8+.
5. Configure database backups, migration execution, health checks, centralized logs, error monitoring, and alerting.
6. Review OpenStreetMap tile, Nominatim, Open-Meteo, and OSRM usage policies; use production-grade providers or self-hosting when traffic exceeds public-service limits.
7. Add automated API integration tests for all role/scope boundaries and browser smoke tests for map layer toggles and responsive layouts.

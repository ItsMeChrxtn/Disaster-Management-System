# Disaster Map – Android app

Flutter client for the Disaster Map platform. It talks to the same PHP API as
the website (`backend/public/api`) and mirrors every website feature:

| Area | Mobile screen |
|---|---|
| Public landing + GIS map (`index.html`, `map.js`) | Landing, Public GIS viewer (layers, municipality/hazard filters, Nominatim search, satellite, my location) |
| Login / register / verify email / forgot / reset | Auth screens (verification code sent through EmailJS, same account as the web) |
| Overview dashboard (cards, charts, active alerts, weather card) | Overview |
| Weather monitoring | Weather |
| Municipalities (admin) | Municipalities (view / add / edit / delete, CSV export) |
| Hazard management (admin, sub admin) | Hazards (rectangle/polygon drawing, vertex editing, GeoJSON upload, covered-locations lookup, filters, CRUD) |
| Safety facilities | Facilities (safe zones + evacuation centers, nearest lookup, car/motorcycle/walking road routing, PSGC barangay + geocoding form, CRUD for managers) |
| Alerts | Alerts (manager draft/send/delete; resident history, read receipts, device notifications every 30 s) |
| Historical disasters | History (admin CRUD, resident read-only) |
| Reports | Reports (generate PDF/XLSX, download + open, delete) |
| Users (admin) | Users (create with temporary password, edit, disable/activate, delete) |
| Profile & password | Profile |

Sub admin scoping (forced municipality, map focus/pan limit) and resident
municipality focus behave like the website.

## Requirements

* Flutter 3.47+ (Dart 3.13+)
* Android SDK 36 with build-tools, Java 17
* `android/key.properties` + `android/keystore/disaster-map-release.jks`
  (both git-ignored). Keep the keystore safe – every future APK must be signed
  with the same key or Android will refuse to install it as an update.

## Build

```bash
cd mobile
flutter pub get
flutter build apk --release --target-platform android-arm,android-arm64
copy build\app\outputs\flutter-apk\app-release.apk ..\frontend\downloads\disaster-map.apk
```

Bump `version:` in `pubspec.yaml` (e.g. `1.0.1+2`) before each release and
update the version text in `frontend/index.html` (`#mobileAppMeta`).

## API server

The default API base URL lives in `lib/config.dart` (`AppConfig.defaultApiUrl`).
Users can change it at runtime from the landing page (server icon) or the login
screen ("API server settings"). For a local XAMPP test on the emulator:

```bash
flutter build apk --debug --dart-define=API_URL=http://10.0.2.2/Disaster-Management-System/backend/public/api
```

## Notes

* Map tiles: OpenStreetMap (street) and Esri World Imagery (satellite).
* Location search / geocoding: Nominatim + Photon, barangay lists from PSGC –
  the same public services the website uses.
* Verification emails are sent from the app through EmailJS using the same
  service/template as `frontend/assets/js/auth-pages.js`. If EmailJS rejects
  non-browser calls, enable "Allow EmailJS API for non-browser applications"
  in the EmailJS account settings.

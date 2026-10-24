# Pag-deploy ng Disaster Map sa bagong Hostinger account

Step-by-step para sa bagong account. Mga 30–45 minuto lahat (ang FTP upload ang
pinakamatagal). Sundan mo lang ang order — may checklist sa dulo ng bawat step.

> **Status: LIVE na ang deploy noong 2026-10-01.**
> Domain: `deeppink-shark-410262.hostingersite.com` · FTP: `82.29.86.104` (port 21,
> user `u995726390`) · DB: `u995726390_disaster_map`.
> Ang gabay sa ibaba ay para sa **susunod** na account o kung kailangang ulitin.
> Para sa maliliit na update, laktawan ang Step 1–7 at gamitin ang
> `node tools/dev/deploy-files.mjs <files>` (nasa dulo).

---

## Bago magsimula

Kailangan mo:

- Hostinger account na may **Premium/Business shared hosting** (kahit anong plan na may MySQL + PHP 8).
- **FileZilla** (libre, https://filezilla-project.org) — ito ang gagamitin sa pag-upload.
  (Pwede rin ang VS Code SFTP extension — nasa dulo ang instructions.)
- Ang folder na ito sa PC mo: `C:\xampp\htdocs\Disaster-Management-System`

---

## Step 1 — Hosting at domain

1. Login sa Hostinger → **hPanel**.
2. Kung wala ka pang domain: hPanel → **Websites → Add website** → piliin ang
   **free temporary domain** (`xxxxx.hostingersite.com`). Pwede na ito pang-defense.
   Kung may sariling domain ka, i-connect mo na ngayon.
3. hPanel → **Advanced → PHP Configuration** → piliin ang **PHP 8.1 o 8.2**.
   Sa tab na *PHP extensions*, siguraduhing naka-check ang: `pdo_mysql`, `mbstring`,
   `gd`, `zip`, `curl`, `openssl`.
4. hPanel → **Security → SSL** → i-install ang free SSL (para `https://`).

✅ *Check:* kapag binuksan mo ang domain mo, may default Hostinger page na lumalabas.

---

## Step 2 — Gumawa ng database

1. hPanel → **Databases → Management**.
2. Punan: database name, username, password → **Create**.
3. **Isulat mo ang tatlong ito** — gagamitin sa Step 5. May prefix silang `u1234567_`:

   ```
   Database:  u________________
   Username:  u________________
   Password:  ________________
   ```

⚠️ Hindi ka pwedeng gumawa ng database gamit ang SQL sa shared hosting — dito lang
sa hPanel. Kaya walang `CREATE DATABASE` sa SQL file natin.

✅ *Check:* nasa listahan na ang database mo sa *Databases → Management*.

---

## Step 3 — Import ang database

1. Sa tabi ng database mo, pindutin ang **Enter phpMyAdmin**.
2. Sa kaliwa, i-click ang pangalan ng database mo (dapat **empty** siya).
3. Tab na **Import** → **Choose File** → piliin:

   ```
   C:\xampp\htdocs\Disaster-Management-System\backend\database\hostinger_import.sql
   ```

4. **Go**. Hintayin ang "Import has been successfully finished".

Ang laman nito: 17 tables + lahat ng data mo (23 municipalities, hazards, safe zones,
evacuation centers, alerts, historical records, users).

✅ *Check:* may 17 tables sa kaliwa. I-click ang `municipalities` → 23 rows.

---

## Step 4 — Kunin ang FTP details

1. hPanel → **Files → FTP Accounts**.
2. Makikita mo ang:

   ```
   FTP IP / Hostname:  ___.___.___.___
   FTP username:       u________.____________
   FTP password:       (kung hindi mo alam, pindutin ang "Change account password")
   Port:               21
   ```

✅ *Check:* nakasulat mo na ang apat na values sa taas.

---

## Step 5 — Gumawa ng `.env` file (sa PC mo muna)

Ang `backend/.env` ang naglalaman ng database password at JWT secret. Hindi ito
kasama sa git kaya kailangan mong gawin nang manu-mano.

1. Buksan ang Notepad.
2. Kopyahin ito, **palitan ang naka-bold na parts** ng galing sa Step 1–2:

   ```
   APP_ENV=production
   APP_DEBUG=false
   APP_URL=https://deeppink-shark-410262.hostingersite.com
   FRONTEND_URL=https://deeppink-shark-410262.hostingersite.com
   DB_HOST=localhost
   DB_PORT=3306
   DB_DATABASE=u995726390_disaster_map
   DB_USERNAME=u995726390_dmadmin
   DB_PASSWORD=ILAGAY-DITO-ANG-PASSWORD-NA-KINOPYA-MO
   TOKEN_TTL_HOURS=24
   JWT_SECRET=d150cc0768b6393217305cdf9a226657af76c62feb5dd9cd814a4d155a06a10e
   JWT_ISSUER=disaster-map-api
   PASSWORD_RESET_TTL_MINUTES=30
   WEATHER_API_URL=https://api.open-meteo.com/v1/forecast
   WEATHER_DEFAULT_LAT=14.2554073
   WEATHER_DEFAULT_LNG=120.8671503
   ```

3. **Save As** → pumunta sa `C:\xampp\htdocs\Disaster-Management-System\backend\`
   → File name: `.env` → **Save as type: All Files** → Save.

⚠️ Mahalaga:
- Walang `https://` sa `DB_HOST` — `localhost` lang talaga.
- Walang espasyo sa paligid ng `=`.
- Walang quotes sa password.
- Ang `JWT_SECRET` sa taas ay bagong random na 64 characters — pwede mo nang gamitin.
  (Kapag pinalitan mo ito mamaya, mapipilitang mag-login ulit lahat.)

✅ *Check:* may `.env` file sa `backend\` folder mo (baka naka-hide ang extension —
tiyakin mong `.env` lang, hindi `.env.txt`).

---

## Step 6 — Upload gamit ang FileZilla

### 6a. Kumonekta

Buksan ang FileZilla → itaas na bar:

```
Host:     ang FTP IP mula Step 4      (hal. 46.202.138.51)
Username: ang FTP username mula Step 4
Password: ang FTP password mula Step 4
Port:     21
```

→ **Quickconnect**. Kapag may lumabas na certificate warning, **OK** lang.

### 6b. Pumunta sa tamang folders

- **Kaliwa (Local site):** `C:\xampp\htdocs\Disaster-Management-System`
- **Kanan (Remote site):** `/domains/<iyong-domain>/public_html`

  ⚠️ Hindi `/public_html` lang! Ang FTP root ay nasa itaas pa — kailangan mong
  pumasok sa `domains/` → pangalan ng domain mo → `public_html`.
  Halimbawa: `/domains/deeppink-shark-410262.hostingersite.com/public_html`

Kung may laman na ang `public_html` (default Hostinger files tulad ng `default.php`),
piliin lahat → right-click → **Delete**.

### 6c. I-upload ang tatlong ito lang

Sa kaliwang panel, i-select ang **tatlo** na ito → right-click → **Upload**:

```
✅ index.php
✅ frontend/          (buong folder)
✅ backend/           (buong folder, kasama ang vendor/ at ang bagong .env)
```

**HUWAG i-upload** (malaki at hindi kailangan sa server):

```
❌ node_modules/      (~200 MB, pang-development lang)
❌ mobile/            (Flutter source, pang-development lang)
❌ tools/             (screenshot scripts)
❌ .git/ at .vscode/  (hidden folders)
❌ docs/              (optional, pwede mong i-upload kung gusto mo)
```

⏱ Tagal: mga 15–25 minuto. Ang `backend/vendor/` ay may libo-libong maliliit na
files kaya mabagal — normal lang `yan. Huwag mo munang isara ang FileZilla.

💡 *Mas mabilis na paraan (ito ang ginamit):* sa halip na FileZilla, puwedeng
script na lang. Ilagay ang FTP details sa `.vscode/sftp.json` (`host`, `port`, `username`,
`password`, `remotePath`), tapos:

```bash
npm install
node tools/dev/deploy-ftp.mjs
```

Nag-i-stage muna ito sa temp folder tapos isang recursive pass lang ang upload —
mga 25 minuto para sa buong 1,494 files / 54 MB. Awtomatiko nitong pinapalitan ang
`backend/.env.production` bilang `backend/.env` sa server, at hindi kasama ang
`node_modules/`, `mobile/`, `tools/`, `.git/`.

### 6d. Tiyaking kumpleto

Sa kanang panel (`/public_html`), dapat ganito ang makikita mo:

```
public_html/
├── index.php
├── frontend/
│   ├── index.html
│   ├── assets/
│   ├── admin/
│   ├── downloads/disaster-map.apk
│   └── .htaccess
└── backend/
    ├── .env          ← dapat nandito
    ├── .htaccess
    ├── app/
    ├── public/
    ├── storage/reports/
    └── vendor/
```

⚠️ Hidden files: FileZilla → menu **Server → Force showing hidden files** para
makita ang `.env` at `.htaccess`.

✅ *Check:* kumpleto ang listahan sa taas, kasama ang `.env` at ang dalawang `.htaccess`.

---

## Step 7 — Permissions sa reports folder

Para makagawa ng PDF/Excel reports ang system:

1. FileZilla → right-click sa `backend/storage/reports` → **File permissions**
2. Numeric value: **755** → OK.

✅ *Check:* `755` na ang permissions ng folder.

---

## Step 8 — Testing (sundan ang order)

Buksan sa browser ang bawat isa:

| # | URL | Dapat lumabas |
|---|-----|---------------|
| 1 | `https://deeppink-shark-410262.hostingersite.com/backend/public/api/health` | `{"success":true,"data":{"service":"disaster-map-api",...}}` |
| 2 | `https://deeppink-shark-410262.hostingersite.com/` | Dapat mag-redirect sa landing page na may mapa |
| 3 | `https://deeppink-shark-410262.hostingersite.com/frontend/login.html` | Login page |
| 4 | `https://deeppink-shark-410262.hostingersite.com/backend/.env` | **403 Forbidden** ← mahalaga ito! |

Kung OK lahat, mag-login ka na gamit ang **sarili mong admin account**.

⚠️ Ang demo accounts na dating kasama sa `hostinger_import.sql`
(`admin@example.gov.ph`, `subadmin@example.gov.ph`, `resident@example.com` — lahat
`Test1234!`) ay **binura na sa live database noong 2026-10-02**. Mga pang-testing lang
ang mga iyon at panganib sa seguridad kapag naiwang buhay sa production.

**Sa bagong deploy:** pagkatapos ng import, agad kang gumawa ng sarili mong admin,
tapos i-delete ang tatlong demo accounts sa **Users** page. Hindi mabubura ang rows
nila (may hawak silang hazards at alerts sa pamamagitan ng `created_by`, na `NOT NULL`),
pero magiging `status=deleted` sila: hindi na gagana ang login at hindi na sila lalabas
sa listahan.

---

## Step 9 — Update ang mobile app sa bagong domain

✅ **Tapos na ito para sa kasalukuyang domain** — naka-upload na ang **v1.4.0**
na naka-turo sa `https://deeppink-shark-410262.hostingersite.com/backend/public/api`.
Kailangan lang ulitin ang nasa ibaba kapag nagpalit ulit ng domain.

Para i-rebuild sa bagong domain:

```bash
cd C:\xampp\htdocs\Disaster-Management-System\mobile
flutter build apk --release --target-platform android-arm,android-arm64 ^
  --dart-define=API_URL=https://deeppink-shark-410262.hostingersite.com/backend/public/api
copy build\app\outputs\flutter-apk\app-release.apk ..\frontend\downloads\disaster-map.apk
```

Tapos i-upload ulit ang `frontend/downloads/disaster-map.apk` via FileZilla.

⚠️ Huwag mong burahin ang `mobile/android/keystore/disaster-map-release.jks` at
`mobile/android/key.properties` — kailangan ng parehong key para ma-update ang app
sa mga phone na naka-install na.

---

## Troubleshooting

| Problema | Solusyon |
|---|---|
| `500 Internal Server Error` sa `/api/health` | Mali ang laman ng `.env` (DB name/user/password) o kulang ang `vendor/`. Pansamantalang gawing `APP_DEBUG=true` para makita ang error, tapos ibalik sa `false`. |
| `404` sa `/api/health` | Kulang ang `backend/public/.htaccess` o hindi nag-upload. I-check sa FileZilla (Force showing hidden files). |
| Blangko ang landing page / walang mapa | Buksan ang browser DevTools (F12) → Console. Kadalasan `404` sa `assets/css/theme.css` → hindi kumpleto ang upload ng `frontend/assets/`. |
| "Invalid credentials" kahit tama | Hindi na-import ang `users` table. Balik sa Step 3. |
| Nakikita ang `.env` sa browser (hindi 403) | Hindi nag-upload ang `backend/.htaccess`. Kritikal ito — i-upload agad. |
| Walang reports na nabubuo | Permissions ng `backend/storage/reports` → gawing `755`. |
| Mabagal/na-stuck ang FTP | FileZilla → Transfer → **Limit number of simultaneous connections** → 2. O gamitin ang ZIP method sa Step 6c. |

---

## Para sa susunod na update ng code

Kapag may binago tayo sa code, hindi mo na kailangang ulitin lahat. Gamitin ang:

```bash
node tools/dev/deploy-files.mjs frontend/assets/js/ui.js frontend/dashboard.html
```

Repo-relative ang mga path at pareho ang pwesto nila sa server. Segundo lang ito
kumpara sa buong deploy.

⚠️ Kapag may binago sa CSS o JS, i-bump ang `?v=` sa `frontend/*.html` (hal.
`theme.css?v=20261001-ds3` → `-ds4`) — kung hindi, lumang version pa rin ang
ipapakita ng browser ng mga user.

Hindi na kailangang i-upload ulit: `vendor/`, `.env`, at ang database.

### Alternative: VS Code SFTP extension (auto-upload on save)

1. VS Code → Extensions → hanapin ang **SFTP** (ni Natizyskunk) → Install.
2. Buksan ang `.vscode/sftp.json` sa project → palitan ang `host`, `username`,
   `password` ng bago mong FTP details (Step 4).
3. Tuwing magse-save ka ng file, awtomatiko na itong ma-a-upload.

⚠️ Ang `.vscode/sftp.json` ay naka-gitignore (may password kasi) — huwag i-commit.

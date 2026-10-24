# Paglipat ng code gamit ang FTP

Para sa Disaster Management System. **Dalawang direksyon:** pag-upload sa Hostinger
(Paraan A at B) at pagkuha pabalik mula doon (nasa gitna). Sa bawat isa, may **script**
(mabilis, ito ang ginagamit natin) at **FileZilla** (manual, kung mas gusto mong nakikita).

---

## Mga detalye ng koneksyon

```
Host (IP) : 82.29.86.104
Port      : 21
Username  : u995726390
Password  : (nasa .vscode/sftp.json — hindi isinusulat dito dahil napupunta ito sa git)
Remote    : /domains/deeppink-shark-410262.hostingersite.com/public_html
```

> ⚠️ **Ang pinakamadalas na pagkakamali:** ang remote path ay **hindi** `/public_html`.
> Ang FTP root ay nasa itaas pa. Kailangan mong dumaan sa
> `domains/` → pangalan ng domain → `public_html`. Kung `/public_html` lang ang
> ilalagay mo, sasabihin ng server na walang ganoong folder.

Kung nakalimutan mo ang FTP password: hPanel → **Files → FTP Accounts** →
**Change account password**. Kapag pinalitan mo, palitan mo rin sa `.vscode/sftp.json`.

---

## Ano ang ipapadala, ano ang hindi

**Ipapadala (1,497 files, 54 MB):**

```
index.php          ang redirect papunta sa frontend/
favicon.ico        icon ng site
frontend/          lahat ng pages, CSS, JS, images, at ang APK (37 MB)
backend/           PHP code + vendor/ (19 MB) + ang .env
```

**HUWAG ipapadala:**

| Folder | Laki | Bakit |
|---|---|---|
| `mobile/` | 3.9 GB | Flutter source at build cache — pang-development lang |
| `node_modules/` | 52 MB | Pang-build lang ng Tailwind at ng mga script |
| `.git/` | 32 MB | History ng repo |
| `tools/` | 29 KB | Mga deploy at screenshot script |
| `docs/` | 32 KB | Dokumentasyon (optional, walang masama kung isama) |
| `.vscode/` | — | **May FTP password** |

Ang `backend/vendor/` ay **kailangan** kahit gitignored — walang Composer sa shared hosting.

---

## Paraan A — Script (inirerekomenda)

### Unang beses pa lang

1. I-install ang Node.js (https://nodejs.org) kung wala pa.
2. Sa project folder:

   ```bash
   npm install
   ```

3. Gumawa ng `.vscode/sftp.json`:

   ```json
   {
     "host": "82.29.86.104",
     "port": 21,
     "username": "u995726390",
     "password": "ANG-FTP-PASSWORD-MO",
     "remotePath": "/domains/deeppink-shark-410262.hostingersite.com/public_html"
   }
   ```

   Naka-gitignore ito — huwag mong i-commit.

4. Siguraduhing may `backend/.env.production` (ito ang production settings; ang
   `backend/.env` ay para sa XAMPP mo at hindi naipapadala).

### Buong upload

```bash
node tools/dev/deploy-ftp.mjs
```

Mga **24 minuto** para sa lahat (1,497 files, 54 MB). May progress na ipinapakita
kada ilang segundo. Ginagawa nito:

- Kinokopya muna ang lahat sa pansamantalang folder, tapos isang recursive pass
  ang upload — mas mabilis kaysa isa-isang folder.
- Awtomatikong pinapalitan ang `backend/.env.production` ng pangalang `backend/.env`
  sa server. **Hindi nagagalaw ang local `.env` mo.**
- Hindi isinasama ang lahat ng nasa listahan sa itaas.

Puwede ring isa lang ang i-upload:

```bash
node tools/dev/deploy-ftp.mjs frontend
node tools/dev/deploy-ftp.mjs backend
```

### Maliit na pagbabago lang

Huwag nang ulitin ang buong 24 minuto:

```bash
node tools/dev/deploy-files.mjs frontend/assets/js/ui.js frontend/dashboard.html
```

Repo-relative ang mga path at pareho ang pwesto nila sa server. Segundo lang ito.

---

## Paraan B — FileZilla (manual)

1. I-download ang FileZilla: https://filezilla-project.org
2. Sa itaas na bar ilagay ang host, username, password, port 21 → **Quickconnect**.
   Kung may certificate warning, **OK** lang.
3. Mga panel:
   - **Kaliwa (Local site):** `C:\xampp\htdocs\Disaster-Management-System`
   - **Kanan (Remote site):** `/domains/deeppink-shark-410262.hostingersite.com/public_html`
4. Menu **Server → Force showing hidden files** — kung hindi, hindi mo makikita ang
   `.htaccess` at `.env`, at kritikal ang dalawang iyon.
5. Sa kaliwa, piliin ang **`index.php`**, **`favicon.ico`**, **`frontend`**, at
   **`backend`** → right-click → **Upload**.
6. Pagkatapos, kailangan mong **i-rename sa server**: ang `backend/.env.production`
   ay gawing `backend/.env` (right-click → Rename). Hindi ito ginagawa ng FileZilla
   nang kusa — ito ang pinaka-madalas na nakakalimutan.

⏱ Mga 25–40 minuto. Ang `backend/vendor/` ang pinakamabagal (libo-libong maliliit
na file). Kung sobrang bagal: **Transfer → Limit number of simultaneous connections → 2**.

---

## Pagkuha ng code PABABA mula sa Hostinger

Kabaligtaran ng nasa itaas — kapag gusto mong hilahin ang nasa server papunta sa
ibang folder o ibang computer.

### Saan nakalagay ang code sa server

```
/domains/deeppink-shark-410262.hostingersite.com/public_html/
├── index.php
├── favicon.ico
├── frontend/          ← pages, CSS, JS, images, APK
└── backend/           ← PHP code, vendor/, at ang .env
```

> ⚠️ **Hindi ito ang buong project.** Ang nasa Hostinger ay ang *tumatakbong website*
> lang. **Wala doon** ang `mobile/` (buong Flutter source ng app), ang `tools/`
> (mga deploy script), ang `docs/`, at ang git history. Kung lilipat ka ng computer,
> **ang local repo o ang GitHub ang kunin mo, hindi ang Hostinger** — kundi mawawala
> ang mobile app mo.

### Paraan A — Script

```bash
# buong site
node tools/dev/download-ftp.mjs C:/backup-hostinger

# isang bahagi lang
node tools/dev/download-ftp.mjs C:/backup-hostinger frontend
node tools/dev/download-ftp.mjs C:/backup-hostinger backend/app
```

Kailangang **walang laman** (o wala pa) ang target folder — tumatanggi ito kung may
laman na, para hindi mapatungan ang ibang trabaho mo. Mga 20–30 minuto ang buong site.

### Paraan B — FileZilla

Pareho ng Paraan B sa itaas, pero baligtad: sa **kanang** panel (server) piliin ang
gusto mong kunin → right-click → **Download**. Tiyaking nakatakda ang kaliwang panel
sa folder na gusto mong pagdalhan.

### ⚠️ May `.env` sa na-download

Kasama sa `backend/.env` ang database password at ang JWT secret. Huwag mo itong
i-commit sa git at huwag ipadala sa iba. Binabalaan ka ng script kapag nakuha ito.

---

## Pagkatapos mag-upload

### 1. Permissions

Right-click sa `backend/storage/reports` → **File permissions** → `755`.
Kung hindi, walang magagawang PDF at Excel reports ang sistema.

### 2. I-check ang apat na ito sa browser

| URL | Dapat lumabas |
|---|---|
| `/backend/public/api/health` | `{"success":true,...}` |
| `/` | Mag-redirect sa landing page |
| `/frontend/login.html` | Login page |
| `/backend/.env` | **403 Forbidden** ← kritikal |

Kung hindi 403 ang pang-apat, nakikita ng kahit sino ang database password mo —
ibig sabihin hindi naipasa ang `backend/.htaccess`. Ayusin agad.

### 3. Cache buster kapag may binago sa CSS o JS

Ito ang madalas na dahilan ng *"bakit hindi nagbabago ang website?"* — luma pa ring
file ang hawak ng browser ng mga user. Palitan ang `?v=` sa lahat ng `frontend/*.html`:

```bash
sed -i "s/theme\.css?v=[0-9a-z-]*/theme.css?v=20261002-ds4/g" frontend/*.html
```

Tapos i-upload ulit ang mga HTML.

---

## Kapag may mali

| Problema | Solusyon |
|---|---|
| `530 Login incorrect` | Ang FTP password ang kailangan, hindi ang database password. Magkaiba ang dalawa kahit pareho ang itsura. |
| `550 No such file or directory` | Mali ang remote path. Hindi `/public_html` — tingnan ang babala sa itaas. |
| `500` sa `/api/health` | Kulang ang `vendor/`, o mali ang `backend/.env`. Pansamantalang gawing `APP_DEBUG=true` para makita ang totoong error, tapos ibalik sa `false`. |
| `404` sa `/api/health` | Hindi naipasa ang `backend/public/.htaccess` (hidden file). |
| Blangko ang page, walang mapa | F12 → Console. Kadalasan `404` sa `assets/css/theme.css` — hindi kumpleto ang upload ng `frontend/assets/`. |
| Nakikita ang `.env` sa browser | Hindi naipasa ang `backend/.htaccess`. **Kritikal** — i-upload agad. |
| Sobrang bagal o na-stuck | Limitahan sa 2 connections, o gamitin ang script sa Paraan A. |

---

## Tandaan

- Hindi nagbabago ang `frontend/config.js` — kinukuha nito ang API URL sa address
  ng page mismo. Kaya kahit palitan ang domain, walang eedit sa website.
- Ang **mobile app** ay kailangang i-rebuild kapag nagpalit ng domain:
  `flutter build apk --release --dart-define=API_URL=https://<domain>/backend/public/api`
- Hindi na kailangang i-upload ulit ang `vendor/`, ang `.env`, at ang database kapag
  code lang ang binago mo.

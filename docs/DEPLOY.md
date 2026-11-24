# Going live: Render (API + database) and Vercel (websites)

Three pieces, all from this repo:

| Piece | Where | Folder | Address (example) |
|---|---|---|---|
| API + PostgreSQL + monthly bills / reminders | Render (company account) | `apps/api`, `infra/render/render.yaml` | `https://pg-api.onrender.com` |
| Owner + resident web app (same app as the phone) | Vercel project 1 | `apps/mobile` | `https://app.<domain>` |
| Landing website | Vercel project 2 | `apps/web` | `https://www.<domain>` |

Everything below was rehearsed locally on 24 Nov 2026 with the production Docker image,
a brand-new empty database, `ENVIRONMENT=production` and both website builds.

## Before you start (have these ready)

- Access to the company Render and Vercel accounts, connected to the company GitHub repo.
- SMTP login for sending email (OTP codes, receipts): host, port, username, password, from-address.
- The owner's name, email and phone for the first login.

## 1. Secrets (generate once, keep in a password manager)

```bash
python -c "import secrets;print(secrets.token_urlsafe(48))"                       # SECRET_KEY
python -c "from cryptography.fernet import Fernet;print(Fernet.generate_key().decode())"  # ENCRYPTION_KEY
python -c "import secrets;print(secrets.token_urlsafe(24))"                       # ADMIN_REGISTRATION_SUPER_KEY
python -c "import secrets;print(secrets.token_hex(16))"                           # ATTENDANCE_DEVICE_KEY
```

**ENCRYPTION_KEY encrypts the KYC documents. If it is lost, those files cannot be opened again.**
Never change it once residents have uploaded documents.

## 2. Render

1. Dashboard → **Environment Groups** → New group `pg-secrets` with:
   `SECRET_KEY`, `ENCRYPTION_KEY`, `ADMIN_REGISTRATION_SUPER_KEY`, `ATTENDANCE_DEVICE_KEY`,
   `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM_EMAIL`, `SMTP_FROM_NAME`,
   `CORS_ORIGINS` = `https://<vercel-app-domain>,https://<vercel-landing-domain>` (exact addresses, comma separated, no `*`),
   `APP_URL` = `https://<vercel-app-domain>` (the "set your password" link in welcome emails points here).
2. **New → Blueprint** → this repo → `infra/render/render.yaml`. It creates the database, the API
   (with a 5 GB disk for encrypted KYC files) and two cron jobs (bills on the 1st at 07:30 IST, reminders daily 09:00 IST).
3. Deploy. Migrations run automatically before traffic switches (`preDeployCommand`).
   The API refuses to start if any secret is missing or weak, and the log names what is missing.
4. Open the API service → **Shell** and create the owner login:
   ```bash
   python scripts/create_owner.py --company "Origin Living" --email owner@company.in --phone 98XXXXXXXX --name "Owner Name" --beds 250
   ```
   It asks for the password (at least 10 characters with upper case, lower case and a number).
5. Check `https://<api>/api/v1/health` shows `"database":"healthy"`.
6. **Check real visitor IPs:** open the app from your phone (mobile data) and from a laptop, then look at the
   API logs. Lines read `... ip=<address> GET /api/v1/...`. You should see your real public IPs.
   If every line shows the same `10.x` address, tell the developer: rate limiting would then treat
   all visitors as one person (FORWARDED_ALLOW_IPS needs adjusting).

## 3. Vercel: owner and resident web app

New Project → same repo → **Root Directory `apps/mobile`**. Settings come from `apps/mobile/vercel.json`.
Environment variable (Production): `EXPO_PUBLIC_API_URL` = `https://<api>` (no trailing slash).
Deploy, then open `/owner-login` and sign in with the owner from step 2.4.

## 4. Vercel: landing website

New Project → same repo → **Root Directory `apps/web`** (framework: Next.js).
Environment variables: `NEXT_PUBLIC_API_URL` = `https://<api>`, `NEXT_PUBLIC_APP_URL` = `https://<app domain>`.

## 5. After both are live

- Put both final Vercel addresses into `CORS_ORIGINS` on Render if they changed, and redeploy the API.
- In the app: **More → Properties** add the home(s), then **Rooms** add rooms (beds are created automatically).
- **Adding residents:** the owner enters only name, mobile and email (bed optional). The resident gets a
  welcome email with a code (valid 48 hours) to set their own password, signs in with email or mobile, and
  fills in their own details and KYC. If the owner hasn't verified their KYC within the deadline
  (Settings, default 7 days), their app access pauses automatically; the owner can switch it back on.
  The daily `pg-kyc-deadlines` cron sends a reminder 2 days before and the "access paused" email. New people can also
  apply themselves ("Join a home" in the app, or the enquiry form on the website).
- **More → Kitchen & meal passes** stays **off** unless the owner wants the food scan.

## Multiple PGs, sign-ups and alerts

- One company runs all its PGs (4 now). Total capacity is shared: 250 beds across all PGs
  (company `bed_limit`). Add each PG under **More → Your PGs**, then its rooms.
- **Join QR code** (More → Join QR code): one poster per PG. New residents scan it, sign up with their
  details (ID photos now or later), and the owner gets an alert: in the app (bell), by email, and as a
  phone notification once the phone app is built with EAS.
- Set `EXPO_PUBLIC_APP_URL` on the web app's Vercel project to its public address (used in the QR link).

## Licence key ("super key"), built but OFF

- `LICENSE_ENFORCED=false` (default): nothing is blocked. Keep it off while testing.
- To sell to another customer later: `python scripts/license_keys.py genkeys` once (keep the private key
  offline), put the public key in `LICENSE_PUBLIC_KEY`, issue a key with
  `LICENSE_PRIVATE_KEY=... python scripts/license_keys.py issue --beds 250 --to "Customer"`, set
  `LICENSE_ENFORCED=true`. The owner enters the key once (API: `POST /api/v1/settings/license/activate`);
  the key fixes the maximum number of beds and cannot be edited or forged.

## Phone apps (iPhone / Android)

Needs an Expo account (free) and, for the stores, Apple Developer (₹ yearly) and Google Play accounts.
Build with `npx eas-cli build -p android` / `-p ios` from `apps/mobile` with `EXPO_PUBLIC_API_URL` set.
`npx eas-cli init` links the app to an Expo project; that project id also switches on phone alerts for owners.
Until then, residents and the owner can use the web app on their phones. It is the same app.

## Not switched on yet (on purpose)

- **Online payment gateway:** residents pay by UPI to the owner's account and the owner confirms with the UTR.
  Razorpay can be added later (`PAYMENT_GATEWAY_PROVIDER`, keys, webhook secret).
- **Demo logins** (`admin/admin`, `0000000000`, `kitchen/kitchen`) exist only in the local demo database.
  The demo seed scripts refuse to run in production, and "demo pay" is disabled there.

## If something goes wrong

- API logs: Render → service → Logs. Every request line has a `request_id` that is also returned to the app.
- Roll back: Render → service → Deploys → pick the previous deploy → Rollback (the database is not rolled back).
- Database backups: Render takes daily backups on paid database plans. Check the plan before go-live.

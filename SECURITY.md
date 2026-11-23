# Security

## Controls in place
| Area | Control |
|---|---|
| Config | Production refuses to boot with default/short `SECRET_KEY`, missing `ENCRYPTION_KEY`, wildcard CORS, mock providers, localhost DB. `ENVIRONMENT` defaults to production, `DEBUG` to false. |
| Auth | bcrypt (12 rounds); 30-min access tokens with `jti`; refresh tokens stored hashed, **rotated on every use, reuse revokes all sessions**; account lockout after 5 failures / 15 min; constant-time login (no user enumeration). |
| Abuse | Per-IP rate limits on login, OTP, registration, refresh. |
| API | Explicit CORS allow-list, security headers (HSTS in prod, nosniff, frame deny), `Cache-Control: no-store`, request IDs, API docs disabled in production, no internal detail in errors, stable error codes. |
| Payments | Webhook/checkout signatures are HMAC-only; mock gateway cannot run in production. |
| KYC | Magic-byte file validation, 5 MB cap, random server-side names, **Fernet encryption at rest**, decrypted only in memory for authorised owners, privacy headers. |
| Data | All money is `NUMERIC`/`Decimal`; deposit ledger is append-only; migrations checked against models in CI. |

## Operational duties
- Back up `ENCRYPTION_KEY` separately from the database: without it KYC files cannot be read.
- Rotate `SECRET_KEY` (logs everyone out) if it is ever exposed.
- Secrets live in the host's secret store (Render environment group), never in git.
- Aadhaar numbers: store only masked numbers; keep document images encrypted; delete KYC files
  after the retention period agreed with the owner (DPDP Act).

## Known limitations
- Rate limiting and lockout are in-process: correct for one API instance. Move to Redis before scaling out.
- Behind a proxy, client IP comes from `X-Forwarded-For`; set `FORWARDED_ALLOW_IPS` to the load balancer.

Report vulnerabilities privately to the repository owner.

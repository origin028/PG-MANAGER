# Demo mode (temporary)

Lets the web app run with **no backend**, on sample data, so it can be shared as a demo.
Everything lives in this folder; the rest of the app touches it only on lines marked `DEMO-MODE`.

| File | Purpose |
|---|---|
| `index.ts` | Answers API calls from `data.json`; applies actions (approve, resolve, record payment, …) in memory |
| `data.json` | Sample API responses for the owner, resident and kitchen roles |
| `demo-entry.tsx` | "Try the demo" buttons on the welcome screen |

## Switch on / off

- **On:** set `EXPO_PUBLIC_DEMO=1` (Vercel → Project → Settings → Environment Variables) and redeploy.
- **Off:** delete that variable, set `EXPO_PUBLIC_API_URL` to the hosted API, redeploy. No code change needed.

Changes made in the demo are kept only until the page is reloaded. Downloads (receipts, CSV) are disabled.

## Remove completely (once the backend is hosted)

```bash
cd apps/mobile
rm -rf src/demo
grep -rln "DEMO-MODE" src | xargs sed -i '' '/DEMO-MODE/d'   # macOS; on Linux use: sed -i '/DEMO-MODE/d'
npm run typecheck && npm run lint
```

Lines that are removed: the imports and one early return in `src/lib/api.ts`, `src/lib/owner.ts`,
`src/lib/download.ts`, and the demo button line in `src/app/(auth)/welcome.tsx`. Each marked line is
self-contained, so deleting it leaves working code.

## Refreshing the sample data

1. Run the API locally with the demo database (`make dev`, seeded by `scripts/seed_demo_pg_data.py` and `seed_demo_extras.py`).
2. Start the app with recording on: `EXPO_PUBLIC_DEMO_RECORD=1 EXPO_PUBLIC_API_URL=http://localhost:8000 npx expo start --web`.
3. Sign in as each role (owner `admin`/`admin`, resident `0000000000`/`0000000000`, kitchen `kitchen`/`kitchen`) and open every screen.
4. In the browser console run `copy(JSON.stringify(__demoDump()))` and paste the result into `data.json`.

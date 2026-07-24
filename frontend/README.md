# Flutter Web frontend (Vercel)

Deploy this folder as a **separate Vercel project** with Root Directory = `frontend`.

The Flutter source lives in `../lib/` (repo root). The sidebar shows **الطلبات** first,
then **إدارة المنيو والأصناف** — see `lib/widgets/admin/admin_sidebar.dart`.

After deploy, verify: `https://<your-frontend>/build-info.json` should show build `1.3.0-orders-sidebar-*`.

## Environment variables (Vercel Project Settings)

| Variable | Required | Example |
|----------|----------|---------|
| `API_BASE_URL` | Recommended | `https://almenupro-backend.vercel.app/api` |

Passed to Flutter at build time via `--dart-define=API_BASE_URL=...`.

## Backend CORS

The Node backend (`apiServer.js`) already sends `Access-Control-Allow-Origin: *` for all API responses.

## Routes

- `/` — customer menu
- `/admin` — admin dashboard (password: see app code)

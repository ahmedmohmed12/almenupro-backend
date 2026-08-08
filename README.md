# AlMenuPro Backend API

Node.js serverless API deployed on Vercel.

## Repository (required for production deploys)

| Setting | Correct value |
|---|---|
| GitHub repo | `ahmedmohmed12/almenupro-backend` |
| Production branch | `main` |
| Root Directory | **empty** (repo root — do **not** set `backend` or `frontend`) |
| Framework Preset | **Other** (not Express) |
| Node.js version | 20.x or 22.x |

> **Important:** Do not connect the `ahmed-almenupro/almenupro` wrapper repo to this Vercel project. That repo has an outdated `vercel.json` without `/api/kitchens` routes.

## Vercel Dashboard checklist

1. Open [Vercel Dashboard](https://vercel.com/dashboard) → project **`almenupro-backend`**
2. **Settings → Git**
   - Connected repository: `ahmedmohmed12/almenupro-backend`
   - Production Branch: `main`
3. **Settings → General**
   - Root Directory: leave blank
   - Framework Preset: **Other**
   - Build Command: use `vercel.json` (or leave override off)
   - Install Command: use `vercel.json`
4. **Settings → Environment Variables** — see [docs/VERCEL_ENV.md](docs/VERCEL_ENV.md)
5. **Deployments** → Redeploy latest `main` after fixing settings

## Entrypoints

| File | Purpose |
|---|---|
| `index.js` | Primary Vercel entrypoint |
| `server.js` | Alternate entrypoint alias |
| `apiServer.js` | Main API router (catch-all `/api/*`) |
| `api/kitchens.js` | `/api/kitchens` CRUD |
| `api/delivery-zones.js` | `/api/delivery-zones` CRUD |

## Verify a successful deploy

```text
GET https://almenupro-backend.vercel.app/api/health
```

Expected fields on a fresh deploy:

```json
{
  "deployTag": "kitchen-zones-v12-github-linked",
  "kitchensApi": true,
  "deliveryZonesApi": true
}
```

```text
GET https://almenupro-backend.vercel.app/api/kitchens?restaurant_id=rest_molton
```

Expected: **HTTP 200** with a JSON array (not `{"error":"Not found"}`).

## GitHub Actions (optional but recommended)

Add these repository secrets in GitHub → Settings → Secrets → Actions:

| Secret | Value |
|---|---|
| `VERCEL_TOKEN` | From Vercel → Account Settings → Tokens |
| `VERCEL_ORG_ID` | `team_vCAhH9T3mI1DAqHFlr085k2L` |
| `VERCEL_PROJECT_ID` | `prj_IV75J5ehG6XuVW9Q9IhyFyhZxeIp` |

Workflow: `.github/workflows/deploy-backend.yml` (runs on every push to `main`).

## Local verify before push

```bash
node scripts/verifyVercelDeploy.js
```

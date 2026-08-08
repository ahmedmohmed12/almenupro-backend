# Vercel environment setup — AlMenuPro

## GitHub ↔ Vercel linkage (backend)

The **`almenupro-backend`** Vercel project must connect to this repository only:

| Setting | Value |
|---|---|
| Repository | `https://github.com/ahmedmohmed12/almenupro-backend` |
| Branch | `main` |
| Root Directory | *(empty — repo root)* |
| Framework | **Other** (not Express) |

If production `/api/health` does not show `deployTag`, the project is likely linked to the wrong repo (`ahmed-almenupro/almenupro`) or using the wrong Root Directory. See [README.md](../README.md).

## Backend project (`almenupro-backend`)

Add these in **Vercel → Project → Settings → Environment Variables**:

| Variable | Production value | Notes |
|---|---|---|
| `MONGODB_URI` | `mongodb+srv://...` | **Required** for persistent data on Vercel |
| `MONGODB_DB` | `almenupro` | Database name |
| `ADMIN_AUTH_SECRET` | long random string | Signs admin JWT tokens |
| `SUPER_ADMIN_USER` | `superadmin` | Platform login username |
| `SUPER_ADMIN_PASSWORD` | strong password | Platform login password |

After adding `MONGODB_URI`, redeploy the backend. Check persistence:

```text
GET https://almenupro-backend.vercel.app/api/health
```

Expected: `"storage": "mongodb"`

## Frontend project (`almenupro-frontend`)

| Variable | Value | Notes |
|---|---|---|
| `API_BASE_URL` | `https://almenupro-backend.vercel.app/api` | Build-time only |
| `SUPER_ADMIN_USER` | `superadmin` | Optional login label default |

**Do not** add `ADMIN_AUTH_SECRET` or `SUPER_ADMIN_PASSWORD` to the frontend project — they would be exposed in the web bundle.

## MongoDB Atlas (free tier)

1. Create cluster at [mongodb.com/atlas](https://www.mongodb.com/atlas)
2. Database Access → create user with read/write
3. Network Access → allow `0.0.0.0/0` (or Vercel IP ranges)
4. Connect → Drivers → copy connection string into `MONGODB_URI`

On first deploy with MongoDB, seed data is copied automatically from bundled JSON files.

## CLI (optional)

```bash
cd backend
npx vercel env add MONGODB_URI production
npx vercel env add ADMIN_AUTH_SECRET production
npx vercel env add SUPER_ADMIN_USER production
npx vercel env add SUPER_ADMIN_PASSWORD production
```

Redeploy both projects after setting variables.

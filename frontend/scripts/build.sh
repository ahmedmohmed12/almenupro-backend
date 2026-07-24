#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FRONTEND_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER_VERSION="${FLUTTER_VERSION:-stable}"
FLUTTER_HOME="${FLUTTER_HOME:-$ROOT/.flutter}"
API_BASE_URL="${API_BASE_URL:-https://almenupro-backend.vercel.app/api}"
SUPER_ADMIN_USER="${SUPER_ADMIN_USER:-superadmin}"

if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
  echo "Installing Flutter ($FLUTTER_VERSION)..."
  git clone https://github.com/flutter/flutter.git -b "$FLUTTER_VERSION" --depth 1 "$FLUTTER_HOME"
fi

export PATH="$FLUTTER_HOME/bin:$PATH"

echo "Almenupro frontend build v1.10.1 (client menu slug routing fix)"

cd "$ROOT"
flutter --version
flutter config --enable-web --no-analytics
flutter precache --web
flutter pub get
flutter build web \
  --release \
  --base-href=/ \
  --no-wasm-dry-run \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=SUPER_ADMIN_USER="$SUPER_ADMIN_USER" \
  --dart-define=BUILD_FEATURE=client-menu-slug-v1.10.1

rm -rf "$FRONTEND_DIR/dist"
mkdir -p "$FRONTEND_DIR/dist"
cp -r "$ROOT/build/web/." "$FRONTEND_DIR/dist/"
cp "$FRONTEND_DIR/dist/index.html" "$FRONTEND_DIR/dist/404.html"

BUILD_ID="1.10.1-client-menu-$(date -u +%Y%m%d%H%M%S)"
printf '{"build":"%s","features":["client-menu-slug","public-restaurant-api","multi-tenant"]}\n' "$BUILD_ID" \
  > "$FRONTEND_DIR/dist/build-info.json"

echo "Frontend build copied to frontend/dist ($BUILD_ID)"

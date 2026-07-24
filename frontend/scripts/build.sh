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

echo "Almenupro frontend build v1.11.0 (platform landing page)"

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
  --dart-define=BUILD_FEATURE=landing-v1.11.0

rm -rf "$FRONTEND_DIR/dist"
mkdir -p "$FRONTEND_DIR/dist"
cp -r "$ROOT/build/web/." "$FRONTEND_DIR/dist/"
cp "$FRONTEND_DIR/landing/index.html" "$FRONTEND_DIR/dist/landing.html"
cp "$FRONTEND_DIR/dist/index.html" "$FRONTEND_DIR/dist/404.html"

BUILD_ID="1.11.0-landing-$(date -u +%Y%m%d%H%M%S)"
printf '{"build":"%s","features":["landing-page","restaurant-persistence","client-menu-slug"]}\n' "$BUILD_ID" \
  > "$FRONTEND_DIR/dist/build-info.json"

echo "Frontend build copied to frontend/dist ($BUILD_ID)"

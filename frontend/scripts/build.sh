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

echo "Almenupro frontend build v1.46.0 (kitchens API + delivery zones UI)"

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
  --dart-define=BUILD_FEATURE=restaurant-kitchen-v1.46.0

rm -rf "$FRONTEND_DIR/dist"
mkdir -p "$FRONTEND_DIR/dist"
cp -r "$ROOT/build/web/." "$FRONTEND_DIR/dist/"
cp "$FRONTEND_DIR/landing/index.html" "$FRONTEND_DIR/dist/landing.html"
cp "$FRONTEND_DIR/dist/index.html" "$FRONTEND_DIR/dist/404.html"

cp "$FRONTEND_DIR/middleware.js" "$FRONTEND_DIR/dist/middleware.js"

node "$FRONTEND_DIR/scripts/prepareVercelOutput.js"

BUILD_ID="1.43.0-kitchen-workflow-$(date -u +%Y%m%d%H%M%S)"
printf '{"build":"%s","features":["kitchen-management","kitchen-kds","zone-kitchen-mapping","cashier-attribution"]}\n' "$BUILD_ID" \
  > "$FRONTEND_DIR/dist/build-info.json"

# Cache-bust bootstrap loader so browsers fetch the latest main.dart.js bundle.
if [ -f "$FRONTEND_DIR/dist/index.html" ]; then
  sed -i "s|flutter_bootstrap.js|flutter_bootstrap.js?v=${BUILD_ID}|g" "$FRONTEND_DIR/dist/index.html"
  sed -i "s|flutter_bootstrap.js|flutter_bootstrap.js?v=${BUILD_ID}|g" "$FRONTEND_DIR/dist/404.html"
fi

echo "Frontend build copied to frontend/dist ($BUILD_ID)"

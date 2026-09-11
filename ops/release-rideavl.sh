#!/usr/bin/env bash
# Publish a RideAVL build over the air (ops/rideavl-ota-updates.md).
#
#   ops/release-rideavl.sh [--required] [--notes "text"] [path/to/app-prod-debug.apk]
#
# Copies the APK into public/rideavl-pilot.apk, backs up the previous one to
# ~/ridepilot-ops, writes public/rideavl-version.json from the versionName /
# versionCode in the rideavl-v2 build.gradle, and stages both for commit.
# Tablets running an older versionCode see the update banner within a minute
# of opening the app. --required blocks sign-in on older builds.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_REPO="${RIDEAVL_REPO:-$HOME/rptest/rideavl-v2}"
APK="${APP_REPO}/android/app/build/outputs/apk/prod/debug/app-prod-debug.apk"
REQUIRED=false
NOTES="Tap Update, then Install."
while [ $# -gt 0 ]; do
  case "$1" in
    --required) REQUIRED=true ;;
    --notes) NOTES="$2"; shift ;;
    *) APK="$1" ;;
  esac
  shift
done
[ -f "$APK" ] || { echo "no APK at $APK (build with: cd $APP_REPO && npm run apk)"; exit 1; }

GRADLE="$APP_REPO/android/app/build.gradle"
VERSION=$(grep -oE 'versionName "[^"]+"' "$GRADLE" | head -1 | cut -d'"' -f2)
CODE=$(grep -oE 'versionCode [0-9]+' "$GRADLE" | head -1 | awk '{print $2}')
[ -n "$VERSION" ] && [ -n "$CODE" ] || { echo "could not read versionName/versionCode from $GRADLE"; exit 1; }

if [ -f public/rideavl-pilot.apk ]; then
  cp public/rideavl-pilot.apk "$HOME/ridepilot-ops/rideavl-pilot.apk.bak-$(date +%Y%m%d-%H%M)"
fi
cp "$APK" public/rideavl-pilot.apk
cp "$APK" "$HOME/ridepilot-ops/rideavl-${VERSION}.apk"

cat > public/rideavl-version.json <<JSON
{
  "version": "${VERSION}",
  "version_code": ${CODE},
  "url": "/rideavl-pilot.apk",
  "required": ${REQUIRED},
  "notes": "${NOTES}",
  "published_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "sha256": "$(sha256sum public/rideavl-pilot.apk | cut -c1-64)"
}
JSON

git add public/rideavl-pilot.apk public/rideavl-version.json
echo "staged RideAVL ${VERSION} (code ${CODE}), required=${REQUIRED}. Now:"
echo "  git commit -m \"Pilot APK: RideAVL ${VERSION}\" && git push"

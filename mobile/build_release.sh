#!/bin/sh
# APK 릴리즈 빌드
# 사용법: sh build_release.sh <BACKEND_URL> <GOOGLE_CLIENT_ID>
# 예시:   sh build_release.sh https://your-backend.railway.app 123456.apps.googleusercontent.com

set -e

API_BASE_URL="${1:?API_BASE_URL 인자 필요}"
GOOGLE_CLIENT_ID="${2:?GOOGLE_CLIENT_ID 인자 필요}"

echo "Building APK..."
echo "  API_BASE_URL  = $API_BASE_URL"
echo "  GOOGLE_CLIENT_ID = $GOOGLE_CLIENT_ID"

puro flutter build apk --release \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID"

echo ""
echo "APK 위치: build/app/outputs/flutter-apk/app-release.apk"

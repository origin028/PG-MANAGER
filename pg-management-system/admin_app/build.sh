#!/bin/bash
set -e

git clone --depth 1 --branch stable https://github.com/flutter/flutter.git /tmp/flutter-sdk

export PATH="/tmp/flutter-sdk/bin:$PATH"

flutter config --enable-web
flutter pub get

flutter build web --release \
  --dart-define=API_BASE_URL=https://pg-management-api.onrender.com/api/v1

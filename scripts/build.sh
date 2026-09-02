#!/usr/bin/env bash
# 乐投 Flutter 多环境打包脚本
# 用法: ./scripts/build.sh [dev|test|pro] [apk|appbundle|ios]
# 说明: APP_ENV=test 对应 Android Flavor=staging

ENV="${1:-dev}"
TARGET="${2:-apk}"
FLAVOR="$ENV"
if [ "$ENV" = "test" ]; then
  FLAVOR="staging"
fi

echo "Building APP_ENV=${ENV} flavor=${FLAVOR} target=${TARGET}..."

case "$TARGET" in
  apk)
    flutter build apk --flavor "$FLAVOR" --dart-define=APP_ENV="$ENV" --release
    ;;
  appbundle)
    flutter build appbundle --flavor "$FLAVOR" --dart-define=APP_ENV="$ENV" --release
    ;;
  ios)
    flutter build ios --flavor "$FLAVOR" --dart-define=APP_ENV="$ENV" --release --no-codesign
    ;;
  *)
    echo "Unknown target: $TARGET"
    exit 1
    ;;
esac

echo "Done."

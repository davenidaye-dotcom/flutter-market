@echo off
cd /d "%~dp0.."
echo [dev] flutter run - use this instead of adb install for daily dev
flutter run --flavor dev --dart-define=APP_ENV=dev --no-enable-impeller
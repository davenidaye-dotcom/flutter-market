@echo off
setlocal EnableExtensions
REM Letou Flutter build script
REM Usage: scripts\build.bat [dev^|test^|pro] [apk^|appbundle^|ios]
REM APP_ENV=test maps to Android flavor=staging
REM
REM ABI must use --target-platform (Gradle abiFilters alone is ignored by Flutter):
REM   dev/test -> android-arm64,android-x64  (phone + LDPlayer)
REM   pro      -> android-arm,android-arm64  (phones)

set "ENV=%~1"
set "TARGET=%~2"
if "%ENV%"=="" set "ENV=dev"
if "%TARGET%"=="" set "TARGET=apk"

set "FLAVOR=%ENV%"
if /I "%ENV%"=="test" set "FLAVOR=staging"

set "PLATFORMS=android-arm64,android-x64"
if /I "%ENV%"=="pro" set "PLATFORMS=android-arm,android-arm64"

echo Building APP_ENV=%ENV% flavor=%FLAVOR% target=%TARGET% platforms=%PLATFORMS% ...

if /I "%TARGET%"=="apk" (
  call flutter build apk --flavor %FLAVOR% --dart-define=APP_ENV=%ENV% --release --target-platform "%PLATFORMS%"
) else if /I "%TARGET%"=="appbundle" (
  call flutter build appbundle --flavor %FLAVOR% --dart-define=APP_ENV=%ENV% --release --target-platform "%PLATFORMS%"
) else if /I "%TARGET%"=="ios" (
  call flutter build ios --flavor %FLAVOR% --dart-define=APP_ENV=%ENV% --release --no-codesign
) else (
  echo Unknown target: %TARGET%
  exit /b 1
)

echo Done.
exit /b %ERRORLEVEL%

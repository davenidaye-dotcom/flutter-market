# 真实联调：登录测试服 + WS，验证倒计时不回跳（复现 01:05↔01:00 必跑）
# 用法: .\scripts\run_live_countdown_test.ps1
# 完整 provider 集成: .\scripts\run_live_countdown_test.ps1 -Full
# 换期断言: .\scripts\run_live_countdown_test.ps1 -Rollover -GameId AZXY10
# 可选: -User player01 -Password Pass1234 -RoomCode 679010 -Seconds 25

param(
  [string]$User = "player01",
  [string]$Password = "Pass1234",
  [string]$RoomCode = "679010",
  [string]$GameId = "JS_SC",
  [int]$Seconds = 20,
  [int]$RolloverMaxSec = 330,
  [switch]$Full,
  [switch]$Rollover
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot\..

Write-Host "=== Live countdown test (real HTTP + WS) ===" -ForegroundColor Cyan
Write-Host "user=$User room=$RoomCode game=$GameId sample=${Seconds}s" -ForegroundColor DarkGray

Write-Host "=== Dart WS probe (推荐，秒级，不走 Flutter HTTP mock) ===" -ForegroundColor Cyan
$env:LIVE_TEST_USER = $User
$env:LIVE_TEST_PASSWORD = $Password
$env:LIVE_TEST_ROOM_CODE = $RoomCode
$env:LIVE_TEST_GAME_ID = $GameId
$env:LIVE_TEST_SAMPLE_SECONDS = "$Seconds"
if ($Rollover) {
  $env:LIVE_TEST_ROLLOVER = "1"
  $env:LIVE_TEST_ROLLOVER_MAX_SEC = "$RolloverMaxSec"
} else {
  Remove-Item Env:LIVE_TEST_ROLLOVER -ErrorAction SilentlyContinue
}
dart run scripts/lottery_countdown_live_probe.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($Full) {
  Write-Host "=== Flutter integration_test (provider 全链路，需编译较慢) ===" -ForegroundColor Cyan
  $integrationArgs = @(
    "test",
    "integration_test/lottery_countdown_live_test.dart",
    "--reporter", "expanded",
    "--dart-define=RUN_LIVE_TESTS=1",
    "--dart-define=APP_ENV=test",
    "--dart-define=LIVE_TEST_USER=$User",
    "--dart-define=LIVE_TEST_PASSWORD=$Password",
    "--dart-define=LIVE_TEST_ROOM_CODE=$RoomCode",
    "--dart-define=LIVE_TEST_GAME_ID=$GameId",
    "--dart-define=LIVE_TEST_SAMPLE_SECONDS=$Seconds"
  )
  flutter @integrationArgs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if ($Rollover) {
  Write-Host "=== AZXY10 rollover integration_test (Provider UI 态) ===" -ForegroundColor Cyan
  flutter test integration_test/lottery_azxy10_rollover_live_test.dart `
    --reporter expanded `
    --dart-define=RUN_LIVE_TESTS=1 `
    --dart-define=APP_ENV=test `
    --dart-define=LIVE_TEST_USER=$User `
    --dart-define=LIVE_TEST_PASSWORD=$Password `
    --dart-define=LIVE_TEST_ROOM_CODE=$RoomCode `
    --dart-define=LIVE_TEST_GAME_ID=$GameId `
    --dart-define=LIVE_TEST_ROLLOVER_MAX_SEC=$RolloverMaxSec
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "Live countdown test passed." -ForegroundColor Green

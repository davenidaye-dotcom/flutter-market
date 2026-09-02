# 聊天/开奖完整回归（数据 + UI，默认跑两轮）
# 改 chat_bet_page / lottery_live_provider / chat_push_cache 前必跑。

param(
  [int]$Rounds = 2,
  [switch]$SkipUi,
  [string]$Device = ""
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot\..

$testArgs = @(
  'test',
  'test/features/lottery/',
  'test/features/lottery/chat_lifecycle_audit_test.dart',
  '--reporter', 'compact'
)
if (-not $SkipUi) {
  $testArgs += 'test/chat_bet_ui_regression_test.dart'
}

for ($i = 1; $i -le $Rounds; $i++) {
  Write-Host "=== Round $i/$Rounds : data+UI regression ===" -ForegroundColor Cyan
  flutter @testArgs
  if ($LASTEXITCODE -ne 0) {
    Write-Host "REGRESSION FAILED (round $i)" -ForegroundColor Red
    exit $LASTEXITCODE
  }
}

if ($Device -ne '' -or $env:RUN_EMULATOR_REGRESSION -eq '1') {
  Write-Host '=== Emulator integration_test ===' -ForegroundColor Cyan
  $emuArgs = @('test', 'integration_test/chat_bet_regression_test.dart', '--reporter', 'expanded')
  if ($Device -ne '') { $emuArgs += @('-d', $Device) }
  flutter @emuArgs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "All regression passed ($Rounds rounds)." -ForegroundColor Green

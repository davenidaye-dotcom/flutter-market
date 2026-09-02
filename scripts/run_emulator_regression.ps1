# 模拟器 UI 回归（需已连接 emulator / 真机）
# 用法: .\scripts\run_emulator_regression.ps1
#       .\scripts\run_emulator_regression.ps1 -Device emulator-5554

param(
  [string]$Device = ""
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot\..

Write-Host '=== 1/2 数据层回归 ===' -ForegroundColor Cyan
flutter test test/features/lottery/ test/chat_bet_ui_regression_test.dart --reporter expanded
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '=== 2/2 模拟器 UI 回归 ===' -ForegroundColor Cyan
$args = @('test', 'integration_test/chat_bet_regression_test.dart', '--reporter', 'expanded')
if ($Device -ne '') { $args += @('-d', $Device) }
flutter @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host 'All regression passed.' -ForegroundColor Green

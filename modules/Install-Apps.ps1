#Requires -Version 5.1
<#
.SYNOPSIS
  winget でアプリを一括インストールする。

.PARAMETER ConfigPath
  apps.json のパス。形式は { "apps": [ { "id": "Google.Chrome", "name": "Google Chrome", "required": true } ] }
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

# winget 存在確認
$winget = Get-Command winget -ErrorAction SilentlyContinue
if (-not $winget) {
    throw 'winget が見つかりません。Windows 11 標準 or Microsoft Store の「アプリ インストーラー」を最新化してください。'
}

if (-not (Test-Path $ConfigPath)) {
    throw "設定ファイルが見つかりません: $ConfigPath"
}

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$apps = $config.apps

if (-not $apps) {
    Write-Host '[SKIP] apps.json に対象アプリがありません'
    return
}

Write-Host "対象アプリ数: $($apps.Count)"

$failed = @()
foreach ($app in $apps) {
    $id = $app.id
    $name = $app.name
    Write-Host ''
    Write-Host "→ $name ($id)" -ForegroundColor White

    # 既にインストール済か確認
    $installed = winget list --id $id --exact --accept-source-agreements 2>&1 | Select-String -Pattern $id
    if ($installed) {
        Write-Host '  [SKIP] 既にインストール済' -ForegroundColor Gray
        continue
    }

    # インストール実行
    try {
        winget install --id $id --exact --silent `
            --accept-package-agreements --accept-source-agreements `
            --disable-interactivity 2>&1 | Tee-Object -Variable wingetOut

        # winget は exit code 0 でも内部失敗があり得るため、再確認
        $verifyInstalled = winget list --id $id --exact --accept-source-agreements 2>&1 | Select-String -Pattern $id
        if ($verifyInstalled) {
            Write-Host "  [OK] $name インストール完了" -ForegroundColor Green
        } else {
            Write-Host "  [WARN] $name インストール後に検出できず" -ForegroundColor Yellow
            $failed += $app
        }
    } catch {
        Write-Host "  [ERROR] $name インストール失敗: $_" -ForegroundColor Red
        if ($app.required -eq $true) {
            $failed += $app
        }
    }
}

if ($failed.Count -gt 0) {
    $names = ($failed | ForEach-Object { $_.name }) -join ', '
    throw "必須アプリのインストールに失敗: $names"
}

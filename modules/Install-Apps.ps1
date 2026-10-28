#Requires -Version 5.1
<#
.SYNOPSIS
  winget でアプリを一括インストールする。

.DESCRIPTION
  - winget が無い／壊れている場合は App Installer の再登録を試みる
  - 既にインストール済のものはスキップ（再実行しても安全）
  - required=true のアプリが入らなかった場合だけ失敗扱い

  Windows PowerShell 5.1 で $ErrorActionPreference='Stop' のまま外部コマンドの
  stderr を 2>&1 で受けると NativeCommandError 例外になるため、本モジュールは
  'Continue' で動かし、失敗判定は明示的に行う。

  常に --source winget を指定する。MSA 社内ネットワークは FortiGate が SSL 検査で
  証明書を差し替えるため、Microsoft Store ソース (msstore) は証明書ピン留めに失敗し
  0x8A15005E「サーバー証明書が、予期された値のいずれにも一致しませんでした」で
  全インストールが止まる。Store ソースは使わない。

.PARAMETER ConfigPath
  apps.json のパス。形式は { "apps": [ { "id": "Google.Chrome", "name": "Google Chrome", "required": true } ] }
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath
)

$ErrorActionPreference = 'Continue'

function Test-WingetAvailable {
    return [bool](Get-Command winget -ErrorAction SilentlyContinue)
}

function Test-AppInstalled {
    param([string]$Id)
    $out = & winget list --id $Id --exact --source winget --accept-source-agreements 2>$null | Out-String
    return ($out -match [regex]::Escape($Id))
}

# ──────────────────────────────────────────────
# winget 存在確認（＋自動修復）
# ──────────────────────────────────────────────
if (-not (Test-WingetAvailable)) {
    Write-Host '[WARN] winget が見つかりません。App Installer の再登録を試みます...' -ForegroundColor Yellow
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
        Start-Sleep -Seconds 3
    } catch {
        Write-Host "  再登録に失敗: $_" -ForegroundColor Yellow
    }
}
if (-not (Test-WingetAvailable)) {
    throw 'winget が使えません。Microsoft Store を開いて「アプリ インストーラー」を更新してから、同じコマンドをもう一度実行してください。'
}

# ソース情報を最新化（新品 PC の初回は古いことがある）
Write-Host 'winget のパッケージ情報を更新中...' -ForegroundColor Gray
& winget source update --name winget --disable-interactivity 2>$null | Out-Null

if (-not (Test-Path $ConfigPath)) {
    throw "設定ファイルが見つかりません: $ConfigPath"
}

$config = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$apps = @($config.apps)

if ($apps.Count -eq 0) {
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

    if (Test-AppInstalled -Id $id) {
        Write-Host '  [SKIP] 既にインストール済' -ForegroundColor Gray
        continue
    }

    # 2>&1 | Out-Host: winget のメッセージを画面と transcript ログの両方に残す（失敗時の切り分け用）
    & winget install --id $id --exact --silent --source winget `
        --accept-package-agreements --accept-source-agreements `
        --disable-interactivity 2>&1 | Out-Host
    $code = $LASTEXITCODE

    if ($code -eq 0 -or (Test-AppInstalled -Id $id)) {
        Write-Host "  [OK] $name インストール完了" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] $name インストールに失敗 (winget exit code: $code)" -ForegroundColor Yellow
        if ($app.required -eq $true) {
            $failed += $app
        } else {
            Write-Host '  必須ではないので続行します' -ForegroundColor Gray
        }
    }
}

if ($failed.Count -gt 0) {
    $names = ($failed | ForEach-Object { $_.name }) -join ', '
    throw "必須アプリのインストールに失敗: $names"
}

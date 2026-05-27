#Requires -Version 5.1
<#
.SYNOPSIS
  Windows の既定設定を MSA 推奨値に揃える。

.DESCRIPTION
  - 電源プラン: バランス（通常）
  - 不要な OOBE 標準アプリ削除（windows-defaults.json で列挙）
  - エクスプローラの拡張子表示・隠しファイル表示を ON
  - タスクバーの「ウィジェット」「チャット」非表示

.PARAMETER ConfigPath
  windows-defaults.json のパス（無くてもデフォルトで動く）
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = ''
)

$ErrorActionPreference = 'Continue'

# ──────────────────────────────────────────────
# 電源プラン: バランス
# ──────────────────────────────────────────────
Write-Host '電源プランをバランスに設定...'
try {
    powercfg /setactive SCHEME_BALANCED 2>&1 | Out-Null
    $active = (powercfg /getactivescheme) -replace '.*\((.*)\).*', '$1'
    Write-Host "  現在の電源プラン: $active" -ForegroundColor Green
} catch {
    Write-Host "  [WARN] 電源プラン設定に失敗: $_" -ForegroundColor Yellow
}

# ──────────────────────────────────────────────
# エクスプローラ設定（拡張子表示・隠しファイル表示）
# ──────────────────────────────────────────────
Write-Host 'エクスプローラの表示設定...'
$explorerKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
try {
    Set-ItemProperty -Path $explorerKey -Name 'HideFileExt' -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $explorerKey -Name 'Hidden' -Value 1 -Type DWord -Force
    Write-Host '  拡張子表示 ON / 隠しファイル表示 ON' -ForegroundColor Green
} catch {
    Write-Host "  [WARN] エクスプローラ設定に失敗: $_" -ForegroundColor Yellow
}

# ──────────────────────────────────────────────
# タスクバー: ウィジェット・チャット非表示
# ──────────────────────────────────────────────
Write-Host 'タスクバーの整理...'
try {
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' `
        -Name 'TaskbarDa' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' `
        -Name 'TaskbarMn' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host '  ウィジェット OFF / チャット OFF' -ForegroundColor Green
} catch {
    Write-Host "  [WARN] タスクバー設定に失敗: $_" -ForegroundColor Yellow
}

# ──────────────────────────────────────────────
# 不要な標準アプリ削除
# ──────────────────────────────────────────────
$defaultRemoveList = @(
    'Microsoft.XboxGamingOverlay',
    'Microsoft.XboxGameOverlay',
    'Microsoft.GamingApp',
    'Microsoft.ZuneMusic',
    'Microsoft.ZuneVideo',
    'Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.BingNews',
    'Microsoft.BingWeather',
    'Microsoft.GetHelp',
    'Microsoft.Getstarted',
    'Microsoft.MicrosoftOfficeHub',
    'Microsoft.MixedReality.Portal',
    'Microsoft.SkypeApp',
    'Microsoft.YourPhone',
    'MicrosoftTeams'  # 個人 Teams (Chat) のみ。組織版 Teams は別 ID
)

$removeList = $defaultRemoveList
if ($ConfigPath -and (Test-Path $ConfigPath)) {
    try {
        $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        if ($cfg.remove_apps) {
            $removeList = $cfg.remove_apps
        }
    } catch {
        Write-Host "  [WARN] 設定ファイル読み込み失敗、デフォルトリストを使用: $_" -ForegroundColor Yellow
    }
}

Write-Host '不要な標準アプリを削除...'
foreach ($appName in $removeList) {
    try {
        $pkg = Get-AppxPackage -Name $appName -ErrorAction SilentlyContinue
        if ($pkg) {
            $pkg | Remove-AppxPackage -ErrorAction SilentlyContinue
            Write-Host "  削除: $appName" -ForegroundColor Green
        }
    } catch {
        # 個別失敗は警告のみで継続
        Write-Host "  [WARN] $appName 削除失敗（無視して継続）" -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host '[OK] Windows 既定設定を適用しました' -ForegroundColor Green

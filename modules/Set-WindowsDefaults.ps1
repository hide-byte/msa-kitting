#Requires -Version 5.1
<#
.SYNOPSIS
  Windows の既定設定を MSA 推奨値に揃える。Dell の不要ソフトも整理する。

.DESCRIPTION
  - 電源プラン: バランス（通常）
  - エクスプローラの拡張子表示・隠しファイル表示を ON
  - タスクバーの「ウィジェット」「チャット」非表示
  - 不要な標準アプリ削除（Microsoft 製ゲーム系・Dell 販促系）
    ※ -AllUsers と Provisioned 削除も行い、後から追加したユーザーにも復活させない
  - McAfee（Dell プリインストール）を winget で削除試行。失敗時は手動案内

.PARAMETER ConfigPath
  windows-defaults.json のパス（無くてもデフォルトで動く）。
  { "remove_apps": [...], "remove_win32_by_name": [...] } で上書き可能
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
    & powercfg /setactive SCHEME_BALANCED 2>$null | Out-Null
    $active = (& powercfg /getactivescheme) -replace '.*\((.*)\).*', '$1'
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
    Set-ItemProperty -Path $explorerKey -Name 'TaskbarDa' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $explorerKey -Name 'TaskbarMn' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host '  ウィジェット OFF / チャット OFF' -ForegroundColor Green
} catch {
    Write-Host "  [WARN] タスクバー設定に失敗: $_" -ForegroundColor Yellow
}

# ──────────────────────────────────────────────
# 不要な標準アプリ削除（Appx）
# ──────────────────────────────────────────────
$defaultRemoveList = @(
    # Microsoft 製（ゲーム・販促・個人向け）
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
    'MicrosoftTeams',              # 旧・個人向け Teams(Chat)。組織版 MSTeams は触らない
    # Dell 製（販促・配信系のみ。SupportAssist / Command Update は保守用に残す）
    'DellInc.DellDigitalDelivery',
    'DellInc.PartnerPromo',
    'DellInc.DellCustomerConnect'
)

# McAfee 等、Appx ではない Win32 アプリを winget で削除試行する名前リスト（部分一致）
$defaultWin32RemoveByName = @(
    'McAfee'
)

$removeList = $defaultRemoveList
$win32RemoveList = $defaultWin32RemoveByName
if ($ConfigPath -and (Test-Path $ConfigPath)) {
    try {
        $cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg.remove_apps) { $removeList = @($cfg.remove_apps) }
        if ($cfg.remove_win32_by_name) { $win32RemoveList = @($cfg.remove_win32_by_name) }
    } catch {
        Write-Host "  [WARN] 設定ファイル読み込み失敗、デフォルトリストを使用: $_" -ForegroundColor Yellow
    }
}

Write-Host '不要な標準アプリを削除...'
foreach ($appName in $removeList) {
    try {
        $pkgs = Get-AppxPackage -AllUsers -Name $appName -ErrorAction SilentlyContinue
        if ($pkgs) {
            $pkgs | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            Write-Host "  削除: $appName" -ForegroundColor Green
        }
        # 新規ユーザー作成時に復活しないよう、プロビジョニング済パッケージも削除
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq $appName } |
            ForEach-Object {
                Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
            }
    } catch {
        Write-Host "  [WARN] $appName 削除失敗（無視して継続）" -ForegroundColor Yellow
    }
}

# ──────────────────────────────────────────────
# Win32 アプリ（McAfee 等）の削除試行
# ──────────────────────────────────────────────
$winget = Get-Command winget -ErrorAction SilentlyContinue
if ($winget -and $win32RemoveList.Count -gt 0) {
    Write-Host 'プリインストールのセキュリティソフト等を確認...'
    foreach ($namePart in $win32RemoveList) {
        $listed = & winget list --name $namePart --accept-source-agreements 2>$null | Out-String
        if ($listed -notmatch [regex]::Escape($namePart)) {
            Write-Host "  $namePart は見つかりませんでした（削除不要）" -ForegroundColor Gray
            continue
        }
        Write-Host "  $namePart を検出。削除を試みます..." -ForegroundColor White
        & winget uninstall --name $namePart --silent --accept-source-agreements --disable-interactivity 2>$null | Out-Null
        $after = & winget list --name $namePart --accept-source-agreements 2>$null | Out-String
        if ($after -match [regex]::Escape($namePart)) {
            Write-Host "  [手動対応] $namePart が残っています。セットアップ完了後に 設定 → アプリ → インストールされているアプリ から削除してください" -ForegroundColor Yellow
        } else {
            Write-Host "  削除: $namePart" -ForegroundColor Green
        }
    }
}

Write-Host ''
Write-Host '[OK] Windows 既定設定を適用しました' -ForegroundColor Green

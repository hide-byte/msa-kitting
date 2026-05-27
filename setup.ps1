#Requires -Version 5.1
<#
.SYNOPSIS
  MSA キッティング メイン処理。bootstrap.ps1 から呼ばれる。

.DESCRIPTION
  ログを開始して各 module を順次実行。失敗時は try/catch でログ保全。

.PARAMETER RepoRoot
  bootstrap.ps1 が展開したリポジトリのルートパス

.NOTES
  Phase 1 / Contract: TC-2026-05-27-002
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RepoRoot,
    # スキップしたいモジュール名（テスト用。例: 'Register-Asset'）
    [string[]]$SkipModules = @()
)

$ErrorActionPreference = 'Stop'

# ──────────────────────────────────────────────
# ログ準備
# ──────────────────────────────────────────────
$logDir = 'C:\msa-kitting-logs'
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $logDir "setup-$timestamp.log"
Start-Transcript -Path $logPath -Append | Out-Null

function Write-Step {
    param([string]$Text)
    Write-Host ''
    Write-Host "▶ $Text" -ForegroundColor Cyan
    Write-Host ('─' * 60) -ForegroundColor DarkGray
}

function Invoke-Module {
    param(
        [string]$Name,
        [string]$Path,
        [string]$SkipKey,
        [hashtable]$Args = @{}
    )
    Write-Step $Name
    if ($script:SkipList -contains $SkipKey) {
        Write-Host "[SKIP] $Name はスキップ指定済 ($SkipKey)" -ForegroundColor Yellow
        return
    }
    if (-not (Test-Path $Path)) {
        Write-Host "[SKIP] モジュール未配置: $Path" -ForegroundColor Yellow
        return
    }
    try {
        & $Path @Args
        Write-Host "[OK] $Name 完了" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] $Name 失敗: $_" -ForegroundColor Red
        Write-Host '失敗ログ全文:' -ForegroundColor Yellow
        Write-Host $_.ScriptStackTrace -ForegroundColor Yellow
        throw
    }
}

$script:SkipList = $SkipModules

# ──────────────────────────────────────────────
# メイン
# ──────────────────────────────────────────────
try {
    Write-Host ''
    Write-Host '╔══════════════════════════════════════════╗' -ForegroundColor Magenta
    Write-Host '║   MSA キッティング Phase 1 セットアップ   ║' -ForegroundColor Magenta
    Write-Host '╚══════════════════════════════════════════╝' -ForegroundColor Magenta
    Write-Host ''
    Write-Host "ログ保存先: $logPath" -ForegroundColor Gray
    Write-Host "リポジトリ: $RepoRoot" -ForegroundColor Gray

    $modulesDir = Join-Path $RepoRoot 'modules'
    $configDir = Join-Path $RepoRoot 'config'

    # Step 1: Windows 既定設定
    Invoke-Module -Name 'Windows 既定設定' `
        -SkipKey 'Set-WindowsDefaults' `
        -Path (Join-Path $modulesDir 'Set-WindowsDefaults.ps1') `
        -Args @{ ConfigPath = (Join-Path $configDir 'windows-defaults.json') }

    # Step 2: アプリ一括インストール
    Invoke-Module -Name 'アプリ一括インストール (winget)' `
        -SkipKey 'Install-Apps' `
        -Path (Join-Path $modulesDir 'Install-Apps.ps1') `
        -Args @{ ConfigPath = (Join-Path $configDir 'apps.json') }

    # Step 3: 端末資産登録（対話）
    Invoke-Module -Name '端末資産登録' `
        -SkipKey 'Register-Asset' `
        -Path (Join-Path $modulesDir 'Register-Asset.ps1') `
        -Args @{ OutputDir = $logDir }

    # 完了サマリ
    Write-Host ''
    Write-Host '════════════════════════════════════════════' -ForegroundColor Green
    Write-Host '  ✅ キッティング Phase 1 完了' -ForegroundColor Green
    Write-Host '════════════════════════════════════════════' -ForegroundColor Green
    Write-Host ''
    Write-Host "次の作業（hide さん or 岡島さんに連絡してください）:" -ForegroundColor Yellow
    Write-Host '  1. Outlook（メール）の設定' -ForegroundColor Yellow
    Write-Host '  2. FortiClient VPN の設定' -ForegroundColor Yellow
    Write-Host '  3. 共有フォルダの接続' -ForegroundColor Yellow
    Write-Host '  4. 複合機（プリンタ）の登録' -ForegroundColor Yellow
    Write-Host ''
    Write-Host "ログ全文: $logPath" -ForegroundColor Gray
    Write-Host ''
}
catch {
    Write-Host ''
    Write-Host '════════════════════════════════════════════' -ForegroundColor Red
    Write-Host '  ❌ キッティング途中で失敗' -ForegroundColor Red
    Write-Host '════════════════════════════════════════════' -ForegroundColor Red
    Write-Host ''
    Write-Host '【次のアクション】' -ForegroundColor Yellow
    Write-Host "  1. ログファイルを開く: $logPath" -ForegroundColor Yellow
    Write-Host '  2. ログ全文をコピー' -ForegroundColor Yellow
    Write-Host '  3. Claude のチャット画面に貼る + 「MSA キッティングで失敗しました」と添える' -ForegroundColor Yellow
    Write-Host '  4. CC の指示に従って次のコマンドを貼る' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}
finally {
    Stop-Transcript | Out-Null
}

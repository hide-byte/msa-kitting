#Requires -Version 5.1
<#
.SYNOPSIS
  MSA キッティング メイン処理。bootstrap.ps1 から呼ばれる。

.DESCRIPTION
  ログを開始して各 module を順次実行。失敗時は try/catch でログ保全。
  失敗は throw で呼び出し元（bootstrap.ps1）に伝える。exit は使わない。
  ログの末尾に必ず "RESULT: SUCCESS" または "RESULT: FAILED" を出す（CI と Claude の判定用）。

.PARAMETER RepoRoot
  bootstrap.ps1 が展開したリポジトリのルートパス

.PARAMETER SkipModules
  スキップしたいモジュール名（テスト用。例: 'Register-Asset'）

.NOTES
  Phase 1。Task Contract は hide さんの CC 環境（~/.claude/contracts）で管理。
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RepoRoot,
    [string[]]$SkipModules = @()
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

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
        [hashtable]$ModuleArgs = @{}
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
        & $Path @ModuleArgs
        Write-Host "[OK] $Name 完了" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] $Name 失敗: $_" -ForegroundColor Red
        Write-Host '失敗箇所:' -ForegroundColor Yellow
        Write-Host $_.ScriptStackTrace -ForegroundColor Yellow
        throw
    }
}

$script:SkipList = $SkipModules
$script:Failed = $false
$script:FailureMessage = ''

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
    Write-Host "PowerShell: $($PSVersionTable.PSVersion)" -ForegroundColor Gray

    $modulesDir = Join-Path $RepoRoot 'modules'
    $configDir = Join-Path $RepoRoot 'config'

    # Step 1: Windows 既定設定（＋Dell 不要ソフト削除）
    Invoke-Module -Name 'Windows 既定設定' `
        -SkipKey 'Set-WindowsDefaults' `
        -Path (Join-Path $modulesDir 'Set-WindowsDefaults.ps1') `
        -ModuleArgs @{ ConfigPath = (Join-Path $configDir 'windows-defaults.json') }

    # Step 2: アプリ一括インストール
    Invoke-Module -Name 'アプリ一括インストール (winget)' `
        -SkipKey 'Install-Apps' `
        -Path (Join-Path $modulesDir 'Install-Apps.ps1') `
        -ModuleArgs @{ ConfigPath = (Join-Path $configDir 'apps.json') }

    # Step 3: 端末資産登録（対話）
    Invoke-Module -Name '端末資産登録' `
        -SkipKey 'Register-Asset' `
        -Path (Join-Path $modulesDir 'Register-Asset.ps1') `
        -ModuleArgs @{ OutputDir = $logDir }

    # 完了サマリ
    Write-Host ''
    Write-Host '════════════════════════════════════════════' -ForegroundColor Green
    Write-Host '  ✅ キッティング Phase 1 完了' -ForegroundColor Green
    Write-Host '════════════════════════════════════════════' -ForegroundColor Green
    Write-Host ''
    Write-Host '残りの手作業（このあと行ってください）:' -ForegroundColor Yellow
    Write-Host '  1. スタートメニューから「Dell Command | Update」を開き、「確認」→ 更新をすべて適用（ドライバ更新）' -ForegroundColor Yellow
    Write-Host '  2. 上の画面に「McAfee が残っています」と出ていたら、設定 → アプリ → インストールされているアプリ から McAfee を削除' -ForegroundColor Yellow
    Write-Host '  3. 設定 → Windows Update → 更新プログラムのチェック → すべて適用して再起動' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'その後、hide さん or 岡島さんに依頼する項目:' -ForegroundColor Yellow
    Write-Host '  - Outlook（メール）の設定' -ForegroundColor Yellow
    Write-Host '  - FortiClient VPN の設定' -ForegroundColor Yellow
    Write-Host '  - 共有フォルダの接続' -ForegroundColor Yellow
    Write-Host '  - 複合機（プリンタ）の登録' -ForegroundColor Yellow
    Write-Host ''
    Write-Host "ログ全文: $logPath" -ForegroundColor Gray
    Write-Host 'RESULT: SUCCESS' -ForegroundColor Green
    Write-Host ''
}
catch {
    $script:Failed = $true
    $script:FailureMessage = "$_"
    Write-Host ''
    Write-Host '════════════════════════════════════════════' -ForegroundColor Red
    Write-Host '  ❌ キッティング途中で失敗' -ForegroundColor Red
    Write-Host '════════════════════════════════════════════' -ForegroundColor Red
    Write-Host ''
    Write-Host "エラー内容: $_" -ForegroundColor Red
    Write-Host ''
    Write-Host '【次のアクション】' -ForegroundColor Yellow
    Write-Host "  1. ログファイルをメモ帳で開く: $logPath" -ForegroundColor Yellow
    Write-Host '  2. Ctrl + A → Ctrl + C で全文コピー' -ForegroundColor Yellow
    Write-Host '  3. Claude のチャット画面に貼る + 「MSA キッティングで失敗しました」と添える' -ForegroundColor Yellow
    Write-Host '  4. Claude の指示に従って次のコマンドを貼る（同じコマンドの再実行で続きから進みます）' -ForegroundColor Yellow
    Write-Host 'RESULT: FAILED' -ForegroundColor Red
    Write-Host ''
}
finally {
    Stop-Transcript | Out-Null
}

if ($script:Failed) {
    throw "キッティング失敗: $($script:FailureMessage)"
}

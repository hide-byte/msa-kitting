<#
.SYNOPSIS
  MSA キッティング ブートストラップ。社員はこの 1 ファイルを起動するだけ。

.DESCRIPTION
  1. 管理者権限チェック
  2. 作業ディレクトリ作成 (C:\msa-kitting)
  3. リポジトリの最新版をダウンロード（GitHub main ブランチの zip）
  4. setup.ps1 を起動

  ※ このファイルは `irm ... | iex` で実行される。iex の中で exit を呼ぶと
    PowerShell ウィンドウごと閉じてエラーが読めなくなるため、exit は一切使わない。
    成否は $global:MSA_KITTING_FAILED（$true / $false）で呼び出し元に伝える。
  ※ このファイルだけは UTF-8 の「BOM なし」で保存する（他の .ps1 は BOM あり）。
    Windows PowerShell 5.1 の irm は BOM を文字 U+FEFF として返すため、BOM があると
    1 行目がコマンド扱いになり param ブロックが先頭でなくなって ParserError になる。
    日本語は HTTP の charset=utf-8 で正しく復号されるので BOM は不要。

.EXAMPLE
  # Win + X → 「ターミナル（管理者）」に貼る:
  Set-ExecutionPolicy Bypass -Scope Process -Force; irm https://raw.githubusercontent.com/hide-byte/msa-kitting/main/bootstrap.ps1 | iex

.NOTES
  Phase 1。Task Contract は hide さんの CC 環境（~/.claude/contracts）で管理。
#>

[CmdletBinding()]
param(
    # GitHub リポジトリの owner/repo
    [string]$RepoSlug = 'hide-byte/msa-kitting',
    # 'latest' = main ブランチ。タグ名を指定するとそのタグの zip を取る
    [string]$Ref = 'latest',
    # 作業ディレクトリ
    [string]$WorkDir = 'C:\msa-kitting',
    # setup.ps1 に渡すスキップ指定（CI 用。例: @('Register-Asset')）
    [string[]]$SkipModules = @()
)

$ErrorActionPreference = 'Stop'
$global:MSA_KITTING_FAILED = $true

# irm | iex では引数を渡せないため、CI 等は環境変数でスキップ指定する（例: MSA_KITTING_SKIP=Register-Asset）
if ($SkipModules.Count -eq 0 -and $env:MSA_KITTING_SKIP) {
    $SkipModules = @($env:MSA_KITTING_SKIP -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

# 日本語・罫線の表示崩れ防止（Windows PowerShell 5.1 対策）
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
# 古い環境で TLS 1.2 が無効な場合の保険
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

function Write-Banner {
    param([string]$Text)
    Write-Host ''
    Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor Cyan
    Write-Host ''
}

function Write-Fatal {
    param([string]$Message, [string[]]$Hints = @())
    Write-Host ''
    Write-Host '════════════════════════════════════════════' -ForegroundColor Red
    Write-Host "  ❌ $Message" -ForegroundColor Red
    Write-Host '════════════════════════════════════════════' -ForegroundColor Red
    foreach ($h in $Hints) { Write-Host "  - $h" -ForegroundColor Yellow }
    Write-Host ''
    Write-Host 'このウィンドウは閉じないでください。' -ForegroundColor Yellow
    Write-Host '上に表示された内容（赤い行とその前後）をコピーして、hide さんに Chatwork で送ってください。' -ForegroundColor Yellow
    Write-Host 'RESULT: FAILED (bootstrap)' -ForegroundColor Red
    Write-Host ''
}

# ──────────────────────────────────────────────
# 1. 管理者権限チェック
# ──────────────────────────────────────────────
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Fatal '管理者権限が必要です' @(
        'キーボードの Win キー + X を押す → 「ターミナル（管理者）」を選ぶ',
        '「このアプリがデバイスに変更を加えることを許可しますか？」→ はい',
        '開いた画面にもう一度コマンドを貼り付けてください'
    )
    return
}

Write-Banner 'MSA キッティング ブートストラップ'

# ──────────────────────────────────────────────
# 2. 作業ディレクトリ
# ──────────────────────────────────────────────
if (-not (Test-Path $WorkDir)) {
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
}
Set-Location $WorkDir

# ──────────────────────────────────────────────
# 3. リポジトリ取得
# ──────────────────────────────────────────────
Write-Host '[INFO] 最新のセットアップ一式をダウンロードしています...' -ForegroundColor Green

$zipUrl = if ($Ref -eq 'latest') {
    "https://github.com/$RepoSlug/archive/refs/heads/main.zip"
} else {
    "https://github.com/$RepoSlug/archive/refs/tags/$Ref.zip"
}

$zipPath = Join-Path $WorkDir 'msa-kitting.zip'
$extractDir = Join-Path $WorkDir 'src'

try {
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
} catch {
    Write-Fatal "ダウンロードに失敗しました: $_" @(
        'Wi-Fi が繋がっているか確認してください（画面右下の Wi-Fi アイコン）',
        'Edge を開いて https://github.com が表示できるか確認してください'
    )
    return
}

try {
    if (Test-Path $extractDir) {
        Remove-Item -Recurse -Force $extractDir
    }
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
} catch {
    Write-Fatal "ダウンロードしたファイルの展開に失敗しました: $_"
    return
}

# 展開後の実体ディレクトリを特定（archive zip は <repo>-<branch>/ で展開される）
$repoRoot = Get-ChildItem -Path $extractDir -Directory | Select-Object -First 1
if (-not $repoRoot) {
    Write-Fatal '展開後のフォルダが見つかりません'
    return
}

# ──────────────────────────────────────────────
# 4. setup.ps1 起動
# ──────────────────────────────────────────────
$setupPath = Join-Path $repoRoot.FullName 'setup.ps1'
if (-not (Test-Path $setupPath)) {
    Write-Fatal "setup.ps1 が見つかりません: $setupPath"
    return
}

Write-Host '[INFO] セットアップを開始します' -ForegroundColor Green
try {
    & $setupPath -RepoRoot $repoRoot.FullName -SkipModules $SkipModules
    $global:MSA_KITTING_FAILED = $false
} catch {
    Write-Fatal "セットアップ途中で失敗しました: $_" @(
        'C:\msa-kitting-logs フォルダを開く',
        '一番新しい setup-日付.log をメモ帳で開く',
        'Ctrl + A → Ctrl + C で全文コピーして hide さんに Chatwork で送る'
    )
    return
}

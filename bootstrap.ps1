#Requires -Version 5.1
<#
.SYNOPSIS
  MSA キッティング ブートストラップ。社員はこの 1 ファイルを起動するだけ。

.DESCRIPTION
  1. 管理者権限チェック
  2. 作業ディレクトリ作成 (C:\msa-kitting)
  3. リポジトリの最新版をダウンロード（GitHub Release zip 経由）
  4. setup.ps1 を起動

.EXAMPLE
  # 管理者として起動した PowerShell に貼る:
  Set-ExecutionPolicy Bypass -Scope Process -Force
  irm https://example.com/bootstrap.ps1 | iex

.NOTES
  Phase 1 / Contract: TC-2026-05-27-002
#>

[CmdletBinding()]
param(
    # GitHub リポジトリの owner/repo
    [string]$RepoSlug = 'OWNER/msa-kitting',
    # Release tag (latest を使う場合は 'latest')
    [string]$Ref = 'latest',
    # 作業ディレクトリ
    [string]$WorkDir = 'C:\msa-kitting'
)

$ErrorActionPreference = 'Stop'

function Write-Banner {
    param([string]$Text)
    Write-Host ''
    Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor Cyan
    Write-Host ''
}

# 1. 管理者権限チェック
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Host '[ERROR] このスクリプトは管理者権限が必要です。' -ForegroundColor Red
    Write-Host 'PowerShell を「管理者として実行」で起動し直してから貼り直してください。' -ForegroundColor Yellow
    exit 1
}

Write-Banner 'MSA キッティング ブートストラップ'

# 2. 作業ディレクトリ
if (-not (Test-Path $WorkDir)) {
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
}
Set-Location $WorkDir

# 3. リポジトリ取得
Write-Host '[INFO] リポジトリを取得しています...' -ForegroundColor Green

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
    Write-Host "[ERROR] リポジトリ取得に失敗: $_" -ForegroundColor Red
    Write-Host '原因候補:' -ForegroundColor Yellow
    Write-Host '  - インターネット接続を確認してください（Wi-Fi 繋がっていますか？）' -ForegroundColor Yellow
    Write-Host '  - Private リポジトリの場合、配布方式（PAT/Release zip）の設定が必要です' -ForegroundColor Yellow
    exit 1
}

if (Test-Path $extractDir) {
    Remove-Item -Recurse -Force $extractDir
}
Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

# 展開後の実体ディレクトリを特定（archive zip は <repo>-<branch>/ で展開される）
$repoRoot = Get-ChildItem -Path $extractDir -Directory | Select-Object -First 1
if (-not $repoRoot) {
    Write-Host '[ERROR] 展開後のディレクトリが見つかりません' -ForegroundColor Red
    exit 1
}

# 4. setup.ps1 起動
$setupPath = Join-Path $repoRoot.FullName 'setup.ps1'
if (-not (Test-Path $setupPath)) {
    Write-Host "[ERROR] setup.ps1 が見つかりません: $setupPath" -ForegroundColor Red
    exit 1
}

Write-Host '[INFO] setup.ps1 を起動します' -ForegroundColor Green
& $setupPath -RepoRoot $repoRoot.FullName

exit $LASTEXITCODE

#Requires -Version 5.1
<#
.SYNOPSIS
  端末番号・利用者名等を対話で取得し、ローカル CSV に追記する。

.DESCRIPTION
  Phase 1: ローカル CSV に保存（C:\msa-kitting-logs\assets-YYYYMMDD.csv）
  Phase 1.5: Google Sheets API 連携を追加（OAuth セットアップ後）

.PARAMETER OutputDir
  CSV の出力先ディレクトリ
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'

function Read-Required {
    param([string]$Prompt)
    while ($true) {
        $val = Read-Host $Prompt
        if (-not [string]::IsNullOrWhiteSpace($val)) {
            return $val.Trim()
        }
        Write-Host '  ※ 入力必須です' -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host '─── 端末資産登録 ───' -ForegroundColor Cyan
Write-Host '岡島さんから渡された情報を入力してください' -ForegroundColor Gray
Write-Host ''

$assetId  = Read-Required '端末番号 (例: MSA-PC-042)'
$userName = Read-Required '利用者名 (例: 三浦 英直)'
$dept     = Read-Host '部署 (空欄可)'
$location = Read-Host '設置場所 (空欄可、例: 本社2F)'

# システム情報を自動取得
$cs = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$os = Get-CimInstance Win32_OperatingSystem

$record = [PSCustomObject]@{
    RegisteredAt   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    AssetId        = $assetId
    UserName       = $userName
    Department     = $dept
    Location       = $location
    ComputerName   = $env:COMPUTERNAME
    Manufacturer   = $cs.Manufacturer
    Model          = $cs.Model
    SerialNumber   = $bios.SerialNumber
    OsName         = $os.Caption
    OsVersion      = $os.Version
    OsBuild        = $os.BuildNumber
    InstallDate    = $os.InstallDate.ToString('yyyy-MM-dd')
}

# コンピュータ名を AssetId に合わせる提案（実行は別途、再起動が必要なため）
if ($env:COMPUTERNAME -ne $assetId) {
    Write-Host ''
    Write-Host '[ヒント] コンピュータ名を端末番号に揃える場合、以下のコマンドを後で実行してください:' -ForegroundColor Yellow
    Write-Host "  Rename-Computer -NewName '$assetId' -Force -Restart" -ForegroundColor Yellow
    Write-Host '  ※ Phase 1 では自動実行しません（再起動が伴うため）'
}

# CSV 出力
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}
$date = Get-Date -Format 'yyyyMMdd'
$csvPath = Join-Path $OutputDir "assets-$date.csv"

if (Test-Path $csvPath) {
    $record | Export-Csv -Path $csvPath -NoTypeInformation -Append -Encoding UTF8
} else {
    $record | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
}

Write-Host ''
Write-Host '[OK] 端末情報を保存しました' -ForegroundColor Green
Write-Host "  CSV: $csvPath" -ForegroundColor Gray
Write-Host ''
Write-Host '内容:' -ForegroundColor Gray
$record | Format-List | Out-String | Write-Host

# TODO Phase 1.5: Google Sheets API への送信を追加
# 設計案: $cfgPath = config/sheets.local.json で SpreadsheetId を持ち、OAuth リフレッシュトークンで認証

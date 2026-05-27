# MSA キッティング自動化

MSA（株式会社マルチサービスエージェント）の新規 Windows PC キッティングを、社員のコピペ操作だけで完結させる仕組み。

## これは何

- 新しい Windows PC を会社で使えるようにする「初期セットアップ」を自動化するスクリプト集
- 社員は管理者 PowerShell に 1 行貼って Enter するだけ
- 失敗したら Claude（CC）に貼って原因解析してもらえる

## Phase 1 のスコープ（このリポジトリの現状）

✅ 含まれるもの
- Windows 標準アプリの不要削除・電源プラン設定
- 標準アプリの一括インストール（Chrome / Acrobat Reader 等、`config/apps.json` で管理）
- 端末番号・利用者名の対話取得 → ローカル CSV 保存（資産台帳の起点）
- 失敗時のログ自動保全

⏳ Phase 1.5 以降（情報入手待ち）
- Outlook（キヤノネット）メール設定
- FortiClient VPN 自動展開
- 社内ファイルサーバ（Share200xxx）マウント
- 複合機ドライバ自動導入

❌ 含まないもの
- Office 本体（ODT 経由のため別 module で対応予定）
- ドメイン参加（キヤノネット運用のためワークグループ前提）
- macOS / Linux 対応

## 使い方（社員向け簡易版）

詳しくは [`docs/employee-guide.md`](docs/employee-guide.md) を読んでください。

**社員に渡す 1 行コマンド**:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; irm https://raw.githubusercontent.com/hide-byte/msa-kitting/main/bootstrap.ps1 | iex
```

途中で「端末番号」「利用者名」を聞かれるので、岡島さんから渡された情報を入力してください。

## 失敗したとき

[`docs/troubleshoot.md`](docs/troubleshoot.md) のテンプレートに沿って、ログファイル全文を Claude のチャット画面に貼ってください。

## hide さん向け運用メモ

- 設定値の追加: `config/apps.json` を編集 → push すれば次回キッティングから反映
- 機密値（VPN PSK 等）: `config/secrets/` は `.gitignore` で除外。1Password 共有 vault 経由 or 対話入力で扱う
- Task Contract: `TC-2026-05-27-002` で Phase 1 のスコープを固定
- 検証: hide さん環境の Windows 11 VM（Hyper-V or UTM）で実機テスト推奨

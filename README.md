# MSA キッティング自動化

MSA（株式会社マルチサービスエージェント）の新規 Windows PC キッティングを、社員のコピペ操作だけで完結させる仕組み。

## これは何

- 新しい Windows PC を会社で使えるようにする「初期セットアップ」を自動化するスクリプト集
- 社員は管理者 PowerShell に 1 行貼って Enter するだけ
- 失敗したら Claude（CC）に貼って原因解析してもらえる

## Phase 1 のスコープ（このリポジトリの現状）

✅ 含まれるもの
- Windows 標準アプリの不要削除・電源プラン設定・エクスプローラ表示設定
- Dell プリインストールの販促系アプリ削除、McAfee の削除試行（失敗時は手動案内）
- 標準アプリの一括インストール（Chrome / Acrobat Reader / Dell Command Update 等、`config/apps.json` で管理）
- 端末番号・利用者名の対話取得 → ローカル CSV 保存（資産台帳の起点）
- 失敗時のログ自動保全（ログ末尾に `RESULT: SUCCESS` / `RESULT: FAILED`）

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

画面付きガイド（仁科さん向け・サインイン不要）: **https://hide-byte.github.io/msa-kitting/**
印刷・Chatwork 添付用 PDF: https://hide-byte.github.io/msa-kitting/MSA-kitting-guide.pdf
文字だけの版: [`docs/employee-guide.md`](docs/employee-guide.md)。ガイドの元ファイルは `docs/index.html`（GitHub Pages が `docs/` を配信）。

**前提（MSA 社内ネットワーク）**: FortiGate (FG-60F) が HTTPS を SSL 検査するため、先に `Fortinet_CA_SSL.cer`（検査用 CA、CN=FGT60FTK21097233）を「信頼されたルート証明機関」に入れないと Web も bootstrap のダウンロードも通らない。ファイルは hide さんが Chatwork で配布する（公開リポには置かない）。同じ理由で winget の Microsoft Store ソースは証明書ピン留めに失敗する（0x8A15005E）ので、スクリプトは `--source winget` 固定。

**社員に渡す 1 行コマンド**:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; irm https://raw.githubusercontent.com/hide-byte/msa-kitting/main/bootstrap.ps1 | iex
```

途中で「端末番号」「利用者名」を聞かれるので、岡島さんから渡された情報を入力してください。

## 失敗したとき

[`docs/troubleshoot.md`](docs/troubleshoot.md) のテンプレートに沿って、ログファイル全文を Claude のチャット画面に貼ってください。

## hide さん向け運用メモ

- 設定値の追加: `config/apps.json` を編集 → push すれば次回キッティングから反映
- ガイド更新: `docs/index.html` を編集 → push で 1〜2 分後に Pages に反映。PDF は再生成が必要（CC に「PDF 作り直して」と依頼）
- 機密値（VPN PSK 等）: `config/secrets/` は `.gitignore` で除外。1Password 共有 vault 経由 or 対話入力で扱う
- Task Contract: `TC-2026-05-27-002` で Phase 1 のスコープを固定
- 検証: push のたびに GitHub Actions の Windows runner で `bootstrap.ps1` → `setup.ps1` を **Windows PowerShell 5.1** で通す（`.github/workflows/smoke-test.yml`）。UTF-8 BOM の有無も CI で落とす
- 文字コード（CI で機械チェック）:
  - `setup.ps1` と `modules/*.ps1` は **UTF-8 BOM 付き** 必須（Windows PowerShell 5.1 は BOM 無しをファイル実行時に Shift-JIS として読み、日本語が化ける）
  - `bootstrap.ps1` だけは **BOM なし** 必須（`irm | iex` で文字列として評価され、5.1 の `irm` は BOM を U+FEFF として返すので 1 行目がコマンド扱いになり ParserError になる）

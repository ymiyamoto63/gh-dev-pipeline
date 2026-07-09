# dev-pipeline

カスタムサブエージェントを使い、要件定義 → 設計 → 実装 → テスト → レビュー → PR作成 の各工程を専任のサブエージェントに委譲する開発パイプライン。要件定義だけを人間との対話で詰め、承認後はエンドツーエンドでエージェントに委譲することを目的とする。Claude Code 版（`agents/` + `commands/`）と GitHub Copilot 版（`copilot/`）の2形式を提供する。

## 構成

```
dev-pipeline/
├── src/                          … 単一ソース（編集するのは常にここだけ）
│   ├── dev-pipeline.md           … オーケストレーターのソース
│   └── <agent>.md                … 6フェーズエージェントのソース
├── agents/                       … 【生成物】Claude Code 版サブエージェント
│   ├── requirements-analyst.md   … 要件定義（requirements.md を出力・更新）
│   ├── software-architect.md     … 設計（design.md を出力）
│   ├── implementer.md            … 実装（implementation-notes.md に追記）
│   ├── test-engineer.md          … テスト・検証（test-report.md を出力）
│   ├── code-reviewer.md          … コードレビュー（review.md を出力）
│   └── pr-publisher.md           … コミット・PR作成（pr-description.md を出力）
├── commands/
│   └── dev-pipeline.md           … 【生成物】上記6エージェントを順に呼び出すオーケストレーター（/dev-pipeline コマンド）
├── copilot/                      … GitHub Copilot 版（VS Code / Copilot CLI 用）
│   ├── agents/                   … 【生成物】オーケストレーター + 6フェーズエージェント（.agent.md）
│   └── prompts/
│       └── dev-pipeline.prompt.md … /dev-pipeline スラッシュコマンド（プロンプトファイル・生成対象外）
├── templates/
│   └── pipeline-config.md        … 対象プロジェクトに置くスタック設定のテンプレート
├── tools/
│   ├── generate.ps1              … src/ から Claude 版 / Copilot 版の両形式を生成（PowerShell）
│   └── generate.sh               … 同上（bash / macOS・Linux・git bash 用）
└── .github/workflows/
    └── generate-check.yml        … push / PR 時に生成物が src/ と一致するか検証
```

各サブエージェントは、対象プロジェクトの `docs/<issue番号>/` ディレクトリにドキュメントを出力する。フェーズ間の受け渡しはこのファイルを介して行われるため、パイプライン実行の記録がそのままプロジェクトに残る。

## パイプラインの流れ

1. **プリフライト** — 作業ツリーがクリーンであることを確認（汚れていればユーザーに確認して停止）
2. **要件定義** (`requirements-analyst`) — タスクを要件定義書に変換。曖昧な点は Open Questions としてユーザーに質問し、回答を渡してエージェント自身が要件書を更新する**インタビューループ**（合計最大20問）。各質問にはコードベース調査に基づく**推奨回答と根拠**が付き、選択肢の先頭に「（推奨）」として提示されるため、デフォルトを受け入れるだけで素早く進められる。各受け入れ基準（AC-1, AC-2, …）には検証方法（自動テスト / 手動確認）のタグが付く
3. **承認ゲート** — ユーザーが要件を承認し、実行モードを選択:
   - **confirm-design**: 設計完了時にもう一度確認を挟む
   - **auto**: 設計〜レビューをノンストップで実行（PR作成前の確認は常にあり）
4. **Issue・ブランチ作成** — 承認後に GitHub Issue を作成し、`docs/<issue番号>/` にドキュメントを移動。`feature/<issue番号>-<slug>` ブランチを作成し、分岐元をベースSHAとして記録。以降の全差分は `ベースSHA..HEAD`
5. **設計** (`software-architect`) — 実装設計書を作成し Issue にコメント。フロント/バック横断の変更では API 契約の明文化が必須
6. **実装** (`implementer`) — 設計のステップごとにスコープを絞って実装。ビルド確認が通ったステップごとに**チェックポイントコミット**（リトライで壊れても直前の正常地点に戻れる）
7. **テスト** (`test-engineer`) — 受け入れ基準を実コマンド実行で検証。失敗時は実装に差し戻して再検証（最大3回）
8. **レビュー** (`code-reviewer`) — `ベースSHA..HEAD` の差分とテストレポートを踏まえてレビュー。指摘があれば実装に差し戻して再検証（最大2回）
9. **PR作成** (`pr-publisher`) — ユーザー確認後、残ファイルをコミットして push、`Closes #<issue番号>` 付きで PR を作成。Issue に最終結果（テスト結果 + PR URL）をコメント

### 中断と再開

オーケストレーターは `docs/<issue番号>/pipeline-state.md` にフェーズ進行・リトライ回数・ブランチ・ベースSHAを常時記録する。セッションが中断しても

```
/dev-pipeline resume #<issue番号>
```

で未完了フェーズから再開できる。

### Lessons learned（失敗の蓄積）

リトライループが発生した場合、原因と予防策が `docs/lessons-learned.md` にフェーズ別セクションで蓄積され、以降の実行で各フェーズのサブエージェントに**該当セクションの抜粋だけ**が渡される。同一根本原因のエントリは重複追加せず既存エントリを更新し、約30件を超えたら統合を提案する。

## インストール（Claude Code 版）

Claude Code のユーザー設定ディレクトリ（`~/.claude/`）に配置する。

### Windows (PowerShell)

```powershell
Copy-Item agents\*.md "$HOME\.claude\agents\" -Force
Copy-Item commands\*.md "$HOME\.claude\commands\" -Force
```

### macOS / Linux

```bash
cp agents/*.md ~/.claude/agents/
cp commands/*.md ~/.claude/commands/
```

配置後、**Claude Code の再起動が必要**（サブエージェント/コマンドディレクトリの監視は、セッション開始時に存在していたディレクトリのみが対象のため）。

## 対象プロジェクト側の設定（pipeline-config.md・推奨）

スタック固有の規約・欠陥パターンはエージェント定義にハードコードせず、**対象プロジェクト側**の `docs/pipeline-config.md` に置く。オーケストレーターが実行開始時にこれを読み、`## stack` を全サブエージェントに、各フェーズ節（`## design` / `## implementation` / `## testing` / `## review` / `## publish`）を対応するフェーズに渡す。

```powershell
# <target-project> は開発対象リポジトリのルート
Copy-Item templates\pipeline-config.md <target-project>\docs\pipeline-config.md
```

テンプレートは Vue 3 + TypeScript + Pinia + Vuetify + Vite + pnpm / Spring Boot + Flyway + PostgreSQL スタックの例になっているので、プロジェクトに合わせて編集する。ファイルがない場合、オーケストレーターはリポジトリからスタックを自動検出して簡易な brief を各エージェントに渡す（精度は config がある方が高い）。いずれの場合も実リポジトリの規約が常に優先される。

## 使い方（Claude Code 版）

```
/dev-pipeline <タスクの説明>
/dev-pipeline resume #<issue番号>     … 中断した実行の再開
```

例:

```
/dev-pipeline ユーザープロフィール編集画面にアバター画像アップロード機能を追加する
```

## GitHub Copilot 版

`copilot/` 配下は同じパイプラインの GitHub Copilot 対応版。VS Code のカスタムエージェント + サブエージェント委譲の仕組みで動作する（`.agent.md` は Copilot CLI でも同形式で読み込まれる）。

### インストール

**対象プロジェクトのリポジトリに**配置する（Claude Code 版と違いユーザーグローバルではなくプロジェクト単位が基本）。

```powershell
# Windows (PowerShell) — <target-project> は開発対象リポジトリのルート
New-Item -ItemType Directory -Force <target-project>\.github\agents, <target-project>\.github\prompts
Copy-Item copilot\agents\*.agent.md <target-project>\.github\agents\ -Force
Copy-Item copilot\prompts\*.prompt.md <target-project>\.github\prompts\ -Force
```

```bash
# macOS / Linux
mkdir -p <target-project>/.github/{agents,prompts}
cp copilot/agents/*.agent.md <target-project>/.github/agents/
cp copilot/prompts/*.prompt.md <target-project>/.github/prompts/
```

全プロジェクト共通で使いたい場合は、VS Code のコマンドパレットから「Chat: New Custom Agent File」→ User を選んでユーザープロファイルに置く（Copilot CLI なら `~/.copilot/agents/`）。

### 使い方

VS Code の Copilot Chat で:

- `/dev-pipeline <タスクの説明>` （プロンプトファイル経由）、または
- エージェントドロップダウンから **dev-pipeline** を選択してタスクを入力

オーケストレーターが `agents` frontmatter に列挙された6つのフェーズエージェントをサブエージェントとして順に呼び出す。各フェーズエージェントは単体でもドロップダウンから直接呼び出せる。

### Claude Code 版との相違点

- **モデル指定なし**: Claude Code 版は全エージェントを `sonnet`（Claude Sonnet 5）に固定しているが（トークン利用料節約のため）、Copilot 版はモデルピッカーの選択に従う。フェーズごとに固定したい場合は各 `.agent.md` の frontmatter に `model: <モデル名>`（モデルピッカー表示名）を追記する
- **ユーザー確認**: Claude Code の AskUserQuestion の代わりに、チャット上で直接質問して回答を待つ
- **ツール名**: `tools` は VS Code の統一ツール名（`read` / `edit` / `search` / `execute` / `web` / `agent` / `todos`）を使用。未知のツール名は無視されるだけなので、旧名しか認識しない環境でも定義自体は壊れない
- パイプラインの流れ・ブランチ運用・pipeline-state・pipeline-config・lessons-learned・リトライ予算は Claude Code 版と同一

## 2形式の生成（単一ソース）

Claude 版（`agents/` + `commands/`）と Copilot 版（`copilot/agents/`）は `src/` の単一ソースから生成される。**編集するのは常に `src/` のみ**。生成物の先頭には AUTO-GENERATED の注記が入っており、直接編集してはいけない（CI が検出して失敗する）。

`src/<name>.md` は3つのセクションからなる:

- `<<<claude>>>` … Claude 版の frontmatter（`---` 行ごとそのまま出力される）
- `<<<copilot>>>` … Copilot 版の frontmatter
- `<<<body>>>` … 共通本文。形式によって文言が異なる箇所だけを `{{claude:〜}}{{copilot:〜}}` とインラインで書き分ける（マーカー内に `}` は使えない。片方の形式にしか存在しない行は、もう片方の出力では行ごと削除される）

`src/` を編集したら生成を実行し、ソースと生成物を一緒にコミットする:

```powershell
.\tools\generate.ps1           # 生成
.\tools\generate.ps1 -Check    # 生成物が src/ と一致するか検証（CI と同じ）
```

```bash
./tools/generate.sh            # 生成
./tools/generate.sh --check    # 検証
```

push / PR 時には GitHub Actions（`generate-check.yml`）が両スクリプトの check モードを実行し、生成し忘れ・生成物の直接編集を検出する。なお `copilot/prompts/dev-pipeline.prompt.md` は Copilot 専用の薄いラッパーのため生成対象外（直接編集してよい）。

## 前提・制約

- スタック固有の知識（規約・欠陥パターン）は対象プロジェクトの `docs/pipeline-config.md` から供給する。テンプレート（`templates/pipeline-config.md`）は SPA（Vue 3 + TypeScript + Pinia + Vuetify + Vite + pnpm / Spring Boot + Flyway + PostgreSQL、devcontainer 開発）の例。実リポジトリの規約が常に優先される
- 設計フェーズでは、クライアント/サーバー横断の変更に対して API 契約（エンドポイント・リクエスト/レスポンス型・エラー応答）の明文化が必須。両サイドはこの契約に対して実装する
- 受け入れ基準には ID（AC-1, AC-2, …）と検証方法タグ（自動テスト / 手動確認）を付与し、テストレポートで基準ごとの検証結果をトレースする
- パイプラインは専用の feature ブランチ上でのみコミットする。`pr-publisher` を含め、main/master への直接コミットや force-push は行わない
- push・PR作成の前には必ずユーザーへの確認を挟む（auto モードでも同様）
- 各サブエージェントは前の対話の記憶を持たない（ステートレス）。フェーズ間の情報は `docs/<issue番号>/` 配下のファイルと、オーケストレーターが抜粋して渡す lessons-learned / pipeline-config を介して受け渡される

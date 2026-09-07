# dev-pipeline

カスタムサブエージェントを使い、要件定義 → 設計 → 実装 → テスト → レビュー → PR作成 の各工程を専任のサブエージェントに委譲する開発パイプライン。要件定義だけを人間との対話で詰め、承認後はエンドツーエンドでエージェントに委譲することを目的とする。Claude Code 版（`agents/` + `commands/`）と GitHub Copilot 版（`copilot/`）の2形式を提供する。

## 構成

```
dev-pipeline/
├── src/                          … 単一ソース（編集するのは常にここだけ）
│   ├── dev-pipeline.md           … オーケストレーターのソース
│   ├── <agent>.md                … 6フェーズエージェントのソース
│   └── ja/                       … 日本語版ソース（手動メンテの翻訳。生成対象外 — 「日本語版ソース」の節を参照）
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
├── gh-dev-pipeline                … gh CLI 拡張のエントリポイント（Copilot 版インストーラー）
└── .github/workflows/
    └── generate-check.yml        … push / PR 時に生成物が src/ と一致するか検証
```

各サブエージェントは、対象プロジェクトの `.scratch/<issue番号>/` ディレクトリにドキュメントを出力する。フェーズ間の受け渡しはこのファイルを介して行われる。

`.scratch/` は git 管理外（プリフライトで `.gitignore` に無ければ追記される）であり、**記録ではなくローカルの作業領域**である。**正本は GitHub Issue 側**に置かれる — 要件定義書は Issue 本文、設計とレビュー結果はコメント、パイプラインの進行状況は `<!-- dev-pipeline:state -->` マーカーを持つ 1 本のコメント（新規投稿ではなく毎回編集して更新される）。したがってクローンし直しても Issue だけで実行内容を再構成でき、リポジトリのコミット履歴にはパイプラインの管理情報が一切混ざらない — レビュー用の差分はパイプラインが書いたコードとちょうど一致する。

`implementation-notes.md` / `test-report.md` / `pr-description.md` は後続フェーズのための作業用の材料であり、意図的にローカル限定としている。

## パイプラインの流れ

1. **プリフライト** — 作業ツリーがクリーンであることを確認（汚れていればユーザーに確認して停止）
2. **要件定義** (`requirements-analyst`) — タスクを要件定義書に変換。入力が既存の要件定義書のパス（[refine-requirements](https://github.com/ymiyamoto63/gh-refine-requirements) の成果物など）の場合は新規作成をスキップし、ドキュメントの「未決定事項」の解消のみ行う（以降の承認ゲート・Issue作成・ブランチ作成は通常どおり実行）。曖昧な点は Open Questions としてユーザーに質問し、回答を渡してエージェント自身が要件書を更新する**インタビューループ**（合計最大20問）。各質問にはコードベース調査に基づく**推奨回答と根拠**が付き、選択肢の先頭に「（推奨）」として提示されるため、デフォルトを受け入れるだけで素早く進められる。各受け入れ基準（AC-1, AC-2, …）には検証方法（自動テスト / 手動確認）のタグが付く
3. **承認ゲート** — ユーザーが要件を承認し、実行モードを選択:
   - **confirm-design**: 設計完了時にもう一度確認を挟む
   - **auto**: 設計〜レビューをノンストップで実行（PR作成前の確認は常にあり）
4. **Issue・ブランチ作成** — 承認後に GitHub Issue を作成し（本文が要件定義書の正本になる）、`.scratch/<issue番号>/` にドキュメントを移動。`feature/<issue番号>-<slug>` ブランチを作成し、分岐元をベースSHAとして記録。以降の全差分は `ベースSHA..HEAD`
5. **設計** (`software-architect`) — 実装設計書を作成し Issue にコメント。フロント/バック横断の変更では API 契約の明文化が必須。全受け入れ基準を実装ステップとテストに対応付ける **AC マッピング**を含み、どのステップにも紐づかない基準は設計時点で検出される
6. **実装** (`implementer`) — 設計のステップごとにスコープを絞って実装。ビルド確認が通ったステップごとに**チェックポイントコミット**（リトライで壊れても直前の正常地点に戻れる）
7. **テスト** (`test-engineer`) — 受け入れ基準を実コマンド実行で検証。失敗時は実装に差し戻して再検証（最大3回）。再検証はまず失敗したテストだけを実行し、通過した場合のみフルスイートに進む
8. **レビュー** (`code-reviewer`) — `ベースSHA..HEAD` の差分とテストレポートを踏まえてレビュー。レビュアーは見つけたものを絞り込まずすべて報告し、各指摘に **要修正 / 任意 / 確度低** のタグを付ける（絞り込むのはオーケストレーター側の仕事）。**要修正** の指摘だけが実装への差し戻しを発生させる（最大2回）。再レビューは前回指摘の解消確認と修正差分に絞られ、ブランチ全体は再レビューしない
9. **PR作成** (`pr-publisher`) — ユーザー確認後、残ファイルをコミットして push、`Closes #<issue番号>` 付きで PR を作成。Issue に最終結果（テスト結果 + PR URL）をコメント

### 中断と再開

オーケストレーターはフェーズ進行・リトライ回数・ブランチ・ベースSHAを、ローカルの `.scratch/<issue番号>/pipeline-state.md` と、Issue 上の state コメント（`<!-- dev-pipeline:state -->` マーカー付き。毎回同じコメントを編集して更新する）の両方に常時記録する。状態が Issue にあるため、セッションが中断しても — 別のマシンやクローンからでも

```
/dev-pipeline resume #<issue番号>
```

で未完了フェーズから再開できる。

### Lessons learned（失敗の蓄積）

リトライループが発生した場合、原因と予防策が `docs/lessons-learned.md` にフェーズ別セクションで蓄積され、以降の実行で各フェーズのサブエージェントに**該当セクションの抜粋だけ**が渡される。同一根本原因のエントリは重複追加せず既存エントリを更新し、約30件を超えたら統合を提案する。

このファイルは `.scratch/` ではなく `docs/` に置き、**リポジトリにコミットする**。特定の Issue に紐づかない横断的なログであり、git 管理外のディレクトリに置くとクローンやマシンを変えた時点で失われ、「失敗の蓄積」という機能自体が静かに無効になるため。

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

スタック固有の規約・欠陥パターンはエージェント定義にハードコードせず、**対象プロジェクト側**の `docs/pipeline-config.md` に置く。オーケストレーターが実行開始時にこれを読み、`## stack` を全サブエージェントに、`## commands`（検証済みビルド/テストコマンド）をビルド・テストを行うフェーズに、各フェーズ節（`## design` / `## implementation` / `## testing` / `## review` / `## publish`）を対応するフェーズに渡す。`## commands` があると各フェーズがコマンドをリポジトリから再発見せずに済み、トークン消費と誤ったコマンド推測の両方が減る（ない場合はオーケストレーターが一度だけ発見して `pipeline-state.md` に記録し、以降のフェーズに確定値として渡す）。

```powershell
# <target-project> は開発対象リポジトリのルート
Copy-Item templates\pipeline-config.md <target-project>\docs\pipeline-config.md
```

テンプレートは Vue 3 + TypeScript + Pinia + Vuetify + Vite + pnpm / Spring Boot + Flyway + PostgreSQL スタックの例になっているので、プロジェクトに合わせて編集する。ファイルがない場合、オーケストレーターはリポジトリからスタックを自動検出して簡易な brief を各エージェントに渡す（精度は config がある方が高い）。いずれの場合も実リポジトリの規約が常に優先される。

## 使い方（Claude Code 版）

```
/dev-pipeline <タスクの説明>
/dev-pipeline <既存の要件定義書のパス>    … refine-requirements 等で作成済みの要件書から開始
/dev-pipeline resume #<issue番号>       … 中断した実行の再開
```

例:

```
/dev-pipeline ユーザープロフィール編集画面にアバター画像アップロード機能を追加する
/dev-pipeline docs/requirements/avatar-upload.md
```

要件定義書のパスを渡した場合、要件定義エージェントによる新規作成はスキップされ、そのドキュメントの「未決定事項」だけをインタビューで解消して承認ゲートに進む。**承認後の GitHub Issue 作成・`.scratch/<issue番号>/` の作成・ブランチ作成は通常実行と同じく必ず行われ**、要件書は Issue 本文（正本）に投稿されたうえで `.scratch/<issue番号>/requirements.md` にコピーされる（`docs/requirements/` の原本はそのまま残る）。

## GitHub Copilot 版

`copilot/` 配下は同じパイプラインの GitHub Copilot 対応版。VS Code のカスタムエージェント + サブエージェント委譲の仕組みで動作する（`.agent.md` は Copilot CLI でも同形式で読み込まれる）。

### インストール

**対象プロジェクトのリポジトリに**配置する（Claude Code 版と違いユーザーグローバルではなくプロジェクト単位が基本）。

#### gh CLI 拡張として（推奨）

```bash
gh extension install ymiyamoto63/gh-dev-pipeline
```

対象リポジトリのルートで実行する（`target-dir` 省略時はカレントディレクトリ）:

```bash
gh dev-pipeline [target-dir]
```

`copilot/agents/*.agent.md` と `copilot/prompts/*.prompt.md` が `<target-dir>/.github/agents/` と `<target-dir>/.github/prompts/` にコピーされる。更新時は再度 `gh extension upgrade dev-pipeline && gh dev-pipeline` を実行する。

#### 手動コピー

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

- **モデル割り当てが異なる**: 両版とも、精度が下流のリトライ回数を最も左右する上流フェーズに強いモデルを、機械的な作業しかしないフェーズに安いモデルを割り当てている（上流の要件・設計の質が上がると下流のリトライが減るため、難しいタスクではトークン総量でもむしろ安くつくことがある）。Copilot 版は複数ベンダーのモデルを選べるため、実装フェーズとレビューフェーズを別系統のモデルにしている — 同一ファミリのモデルは同じ盲点を共有するので、実装を書いたモデルとは別系統でレビューさせるほうが見落としが減る

  | フェーズ | Claude Code 版 | Copilot 版 |
  | --- | --- | --- |
  | `dev-pipeline`（オーケストレーター） | 親セッションのモデル | Claude Opus 5 |
  | `requirements-analyst` | `opus` | Claude Opus 5 |
  | `software-architect` | `opus` | Claude Opus 5 |
  | `implementer` | `sonnet` | Claude Sonnet 5 |
  | `test-engineer` | `sonnet` | Claude Sonnet 5 |
  | `code-reviewer` | `sonnet` | GPT-5.6 Terra |
  | `pr-publisher` | `haiku` | Claude Haiku 4.5 |

  Copilot 版の値は**モデルピッカーの表示名をそのまま書く**必要がある（`opus` のような抽象エイリアスは使えない）。組織のモデルポリシーで無効なモデルを指定するとエージェントの読み込み自体が失敗するので、モデル追加・廃止のたびに Copilot CLI の `/model` で実在する表示名を確認すること。VS Code の Copilot Chat はフォールバック指定として配列（`model: [A, B]`）も受け付けるが、Copilot CLI は文字列しか受け付けない（`Expected string, received array` で落ちる）ため、**スカラー文字列で書く**
  変更するときは `src/<agent>.md` の該当 frontmatter（claude 側 / copilot 側）の `model` を編集して再生成する。Claude Code 版で親セッションのモデルを継承させたい場合は `model` 行を削除する
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

## 日本語版ソース（src/ja/）

`src/ja/` は `src/` の手動メンテの日本語訳で、エージェント定義の指示文そのものを日本語で読みたい場合のためのもの（生成スクリプトの対象外）。

**通常は英語版（`src/` からの生成物）の利用を推奨する。** 出力されるドキュメント・コミットメッセージ・Issue はどちらの版でも日本語になる（定義内で明示指定しているため）。一方、定義文自体は日本語の方がトークン密度が高く、日本語版はサブエージェント呼び出しごとに英語版の約 1.5〜2 倍のトークンを消費する（実測: オーケストレーターのソースは英語版 16KB に対し日本語版 23KB）。指示の遵守精度も英語の方が下がらない。「定義は英語・出力は日本語」が精度・コストの両面で最適な組み合わせになる。

`src/` を変更した場合は `src/ja/` にも同じ変更を反映すること。

## プロンプト設計の方針

エージェント定義は Anthropic の [プロンプティングのベストプラクティス](https://platform.claude.com/docs/ja/build-with-claude/prompt-engineering/claude-prompting-best-practices)、[Claude Opus 5 のプロンプティング](https://platform.claude.com/docs/ja/build-with-claude/prompt-engineering/prompting-claude-opus-5)、[Claude Sonnet 5 のプロンプティング](https://platform.claude.com/docs/ja/build-with-claude/prompt-engineering/prompting-claude-sonnet-5)、および [Claude 5 世代のコンテキストエンジニアリングの新ルール](https://claudefa.st/blog/guide/mechanics/claude-5-context-engineering) に沿っている（要件定義・設計エージェントは Opus 5、実装・テスト・レビューは Sonnet 5 で動くため、両モデルのガイドが対象になる）。`src/` を編集する際は以下を崩さないこと。

- **成果物の分量を明示的に抑える** — Opus 5 はディスクに書くドキュメントが長くなりがちなので、文書を書く各フェーズに「中身は網羅しつつ埋め草・言い換えの要約・定型文は省く」旨を持たせている
- **冗長なナレーションを抑える** — オーケストレーターの `<tone_preference>` ブロックで、フェーズ間は1行の状況報告に留め、前置きではなく結果から書き出させる。エフォート設定では応答の長さは制御できないため、プロンプトで明示する必要がある
- **検証指示を重ねない** — 「最終確認ステップを入れる」「回答を再確認する」「サブエージェントで検証する」といった指示は、Opus 5 が既に自前でやっていることと重複して過剰検証を招くので追加しないこと。検証は実コマンドを走らせる `implementer` / `test-engineer` の実作業としてのみ持たせる
- **委譲に上限を設ける** — オーケストレーターの「委譲の規律」で、生成するサブエージェントを6つのフェーズエージェントに限定し、調査用・検証用の追加エージェントを禁じている
- **レビューは絞り込ませず、フィルタは呼び出し元に置く** — 「重大な指摘のみ報告」「保守的に」といった指示はモデルが文字通り従って報告件数を落とす。レビューを担う Sonnet 5 は絞り込み指示への追従がさらに忠実で、「調査はしたが報告しない」という形で再現率が落ちるため、レビュアー定義には「この段階の目標はカバレッジであり、絞り込みは下流が行う」ことを明記する。`code-reviewer` には全件報告 + 深刻度タグ付けをさせ、どれがゲートになるかはオーケストレーターが決める。省いてよいものの基準は「重要なもの」のような質的な語ではなく具体的に書く（フォーマッタが管理する純粋な整形の好みのみ）
- **指示の適用範囲を明示する** — Sonnet 5 は指示を文字通り・明示的に解釈し、1つの項目への指示を他の項目へ暗黙に一般化しない。広く適用したい指示は範囲を明示する（例:「変更した全サイドのテストスイートを実行」「すべての受け入れ基準を表に載せる」）
- **ルールは実際の失敗モードに紐づける** — Claude 5 世代には過剰なガードレールがかえって判断を圧迫する。「〜しないこと」系のルールを増やすのは、モデルが自力で回避できない失敗モードが実際に観測された場合だけにする（lessons-learned がその記録装置）。判断で足りるところはルールの列挙ではなく判断基準で書く（例: コメント規則の箇条書きではなく「周辺コードのコメント密度・命名・イディオムに合わせる」）
- **コンテキストは絞って渡し、実物を指し示す** — サブエージェントには lessons-learned / pipeline-config の該当フェーズの抜粋だけを渡し、前フェーズの成果物は本文を貼らずファイルパスで指し示す（要約の又聞きより実物の参照 — テストレポートのエラー出力を言い換えて渡さない）
- **スコープを明示的に固定する** — 各フェーズに「依頼されたスコープのまま出す。より良い案があれば一文で述べたうえで依頼どおり進める」を持たせ、勝手な範囲拡大を防ぐ
- **煽った言い回しを使わない** — `CRITICAL:` / `You MUST use this tool when...` のような強調はツールやスキルの過剰トリガーを招く。通常の指示文で書く

## 前提・制約

- スタック固有の知識（規約・欠陥パターン）は対象プロジェクトの `docs/pipeline-config.md` から供給する。テンプレート（`templates/pipeline-config.md`）は SPA（Vue 3 + TypeScript + Pinia + Vuetify + Vite + pnpm / Spring Boot + Flyway + PostgreSQL、devcontainer 開発）の例。実リポジトリの規約が常に優先される
- 設計フェーズでは、クライアント/サーバー横断の変更に対して API 契約（エンドポイント・リクエスト/レスポンス型・エラー応答）の明文化が必須。両サイドはこの契約に対して実装する
- 受け入れ基準には ID（AC-1, AC-2, …）と検証方法タグ（自動テスト / 手動確認）を付与し、テストレポートで基準ごとの検証結果をトレースする
- パイプラインは専用の feature ブランチ上でのみコミットする。`pr-publisher` を含め、main/master への直接コミットや force-push は行わない
- push・PR作成の前には必ずユーザーへの確認を挟む（auto モードでも同様）
- 各サブエージェントは前の対話の記憶を持たない（ステートレス）。フェーズ間の情報は `.scratch/<issue番号>/` 配下のファイルと、オーケストレーターが抜粋して渡す lessons-learned / pipeline-config を介して受け渡される

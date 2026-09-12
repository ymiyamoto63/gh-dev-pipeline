---
name: dev-pipeline
description: 機能追加・バグ修正を、要件定義 → 設計 → 実装 → テスト → レビュー → PR作成の各フェーズに通し、各フェーズを専任のサブエージェントに委譲する。
argument-hint: <タスクの説明> | <既存の要件定義書へのパス> | resume #<issue番号>
agent: dev-pipeline
---

このコマンドで指示されたタスクを、エージェント定義に従って開発パイプライン全体（要件定義 → 設計 → 実装 → テスト → レビュー → PR作成）に通してください。コマンドの後にユーザーが入力したテキストがタスクの説明です。それが既存の要件定義書へのパス（例: refine-requirements スキルが作成した `docs/requirements/<feature-slug>.md`）である場合は、エージェント定義に従いフェーズ1をその文書から開始してください — 承認ゲート、GitHub Issue の作成、`.scratch/<issue番号>/` の準備は通常どおり実行します。`resume #<issue番号>` である場合は、エージェント定義に従い、Issue の state コメントから中断した実行を再開してください。

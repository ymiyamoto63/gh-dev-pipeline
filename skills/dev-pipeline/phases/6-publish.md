<!-- 自動生成ファイル: dev-pipelineリポジトリ（https://github.com/ymiyamoto63/gh-dev-pipeline）の src/dev-pipeline.md から生成。編集はそのリポジトリの src/dev-pipeline.md で行い tools/generate.ps1（または tools/generate.sh）を実行して再生成し、生成物をコピーし直すこと。インストール先にコピーされたこのファイルを直接編集しないこと（次回の更新で上書きされる）。 -->
### 6. 公開（Publish）

autoモードであっても、常にまず明示的な確認をユーザーに求める。リモートへのpushとPRのオープンは、目に見える、後戻りしにくい操作であるため。

確認が得られたら、`.scratch/<issue番号>/requirements.md`、`.scratch/<issue番号>/design.md`、`.scratch/<issue番号>/test-report.md`を指し示し、ベースSHAとissue番号を渡してsubagent_type `pr-publisher`を呼び出す。pr-publisherは、未コミットのまま残っているコードをコミットし（パイプライン自身の文書は無視されており、コミットに入ることはない）、`.scratch/<issue番号>/pr-description.md`を保存し、pushして、Issueがマージ時に自動的にクローズされるよう本文に`Closes #<issue番号>`を入れてPRを開く。

**PR作成後。**

1. Issueにクロージングコメントを投稿する。見出し`## テスト結果`に`.scratch/<issue番号>/test-report.md`（最新の実行のもの）を続け、末尾にPR URLを添えて投稿する。テストコードにはAC IDを書かないので、受け入れ基準と実テストの対応が残る場所はこのコメントのカバレッジ表だけである。
2. `pipeline-state.md`とstateコメントのフェーズ6を完了にマークする。これについてコミットするものはない。

`pr-publisher`が公開せずに停止した場合（`gh`未認証、リモートなし、秘密情報の疑い、誤ったブランチ）は、次回の実行が同じブロッカーに引っかからないよう、「Lessons learned」の形式でlessonエントリを追記する。

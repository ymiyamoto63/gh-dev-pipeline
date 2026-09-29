<!-- 自動生成ファイル: dev-pipelineリポジトリ（https://github.com/ymiyamoto63/gh-dev-pipeline）の src/dev-pipeline.md から生成。編集はそのリポジトリの src/dev-pipeline.md で行い tools/generate.ps1（または tools/generate.sh）を実行して再生成し、生成物をコピーし直すこと。インストール先にコピーされたこのファイルを直接編集しないこと（次回の更新で上書きされる）。 -->
### 4. テスト（Testing）

`.scratch/<issue番号>/requirements.md`、`.scratch/<issue番号>/design.md`（そのテスト戦略節）、`.scratch/<issue番号>/implementation-notes.md`を指し示して、subagent_type `test-engineer`を呼び出す。どちら側が変更されたかを伝える: 変更されたすべての側（フロントエンドおよび/またはバックエンド）のテストスイートを実行しなければならず、片方だけではいけない。`.scratch/<issue番号>/test-report.md`に書き込まれる。

失敗が報告された場合:

1. 新しい`implementer`呼び出しに差し戻して修正させる。言い換えず、`.scratch/<issue番号>/test-report.md`（正確なコマンドとエラー出力）を指し示す。
2. 修正をチェックポイントコミットする。
3. `test-engineer`を**失敗にスコープを絞って**再実行する。どのテスト/スイートが失敗したかを正確に伝え、まずそれらを再実行させ、通過した場合に限り同じ呼び出しの中で関連するフルスイートに進ませる。リトライのたびにフルスイート実行のコストを払わない。
4. 最大3回繰り返す。それでも失敗する場合は、ループを続けずに停止し、ユーザーにブロッカーを報告する。
5. 修正できた場合も、予算が尽きた場合も、「Lessons learned」の形式でlessonエントリを追記する。

<!-- 自動生成ファイル: dev-pipelineリポジトリ（https://github.com/ymiyamoto63/gh-dev-pipeline）の src/dev-pipeline.md から生成。編集はそのリポジトリの src/dev-pipeline.md で行い tools/generate.ps1（または tools/generate.sh）を実行して再生成し、生成物をコピーし直すこと。インストール先にコピーされたこのファイルを直接編集しないこと（次回の更新で上書きされる）。 -->
### 3. 実装（Implementation）

設計の実装ステップを、次の基準でまとめたうえで、まとまりごとに1回、subagent_type `implementer`を呼び出す。`.scratch/<issue番号>/requirements.md`と`.scratch/<issue番号>/design.md`の該当部分、加えて正確なファイルパスを指し示す。各呼び出しは`.scratch/<issue番号>/implementation-notes.md`に追記していく。

- まとめ方: 触れるファイルが重なるステップ、または同じ層で互いに依存する小さなステップ（合わせて変更ファイルが概ね5つ以下）は1回の呼び出しにまとめる。DBマイグレーション・バックエンド・フロントエンドのように層をまたぐステップは、層ごとに分ける。呼び出しのたびに要件・設計とリポジトリを読み直すため、細かく分けるほど読み込みが増える。
- 設計のステップ順に従う。境界をまたぐ変更では典型的にDBマイグレーション → バックエンド → フロントエンドの順になり、各ステップがコンパイル可能な状態の上に積み上がる。
- 各呼び出しの検証が通過したら、そのファイルをチェックポイントコミットし、stateコメントを更新する。メッセージは`step <n>/<total>: <ステップ名> (#<issue番号>)`のような形（まとめた場合は`step 1-2/4: ...`）。
- 最後のステップの後、テストフェーズに進む前に、`git diff <base SHA> --stat`でブランチが設計の「影響を受けるファイル」リストと一致する変更を含んでいることを確認する。`.gitignore`と`<config_dir>/lessons-learned.md`はこの比較から除く。

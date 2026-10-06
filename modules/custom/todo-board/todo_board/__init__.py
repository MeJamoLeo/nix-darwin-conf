"""todo-board — 日次 Todo ファイルの確定（roll）・▶/■ 刻み（pick）・追記（add）・Canvas／メール取得（sync）。

標準ライブラリのみ。依存の向き: store ← items ← backlog / daily ← planner / gcal / llm / canvas / mail / blocks ← commands ← cli。
各モジュールの docstring に、その責務の設計メモ（なぜそうしたか）がある。

  store     パス・base・env・原子的書き込み・状態／ステータス・除外／別名設定
  items     タスク行の解析・描画、マーカー、作業量、日付
  backlog   倉庫 backlog.md の見出しブロックの読み書き
  daily     日次ファイルの構造・繰り越し・集計・フッタ・Done today・harvest/refresh_today
  planner   着手期限と Today／Overdue／If time allows の選択
  canvas    Canvas トークン・API・lock_at キャッシュ・倉庫 Canvas 欄
  mail      メール digest の取り込み・倉庫 Mail 欄
  gcal      Google カレンダーの 📕 予定を試験として取り込む（claude -p ＋ Calendar コネクタ）
  llm       claude -p の共通呼び出し
  blocks    record-blocks の作業時間を今日の行へ (≈35m) として紐づける
  commands  roll / sync / pick / add / edit / show
  cli       argparse と main()
"""

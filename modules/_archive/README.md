# _archive — 退役トピック置き場

無効化の唯一の正規手順：トピックのディレクトリをここへ移し、profile の import を消す。
復帰はその逆（ディレクトリを戻して profile に import 1行）。
「import をコメントアウトしてファイル温存」「flake.nix でコメントアウト」等の
ばらばらな無効化はしない。

## 現在の住人

- **cmux/** — cmux 引退（2026-07、Ghostty + herdr へ移行）。cmux.json 管理を停止。
- **network-block/** — /etc/hosts ベースのドメインブロック。flake.nix でコメントアウト
  されていた（=無効）状態を正規化してここへ。復帰時は postActivation の
  /etc/hosts 競合警告（ファイル内コメント）を再読すること。

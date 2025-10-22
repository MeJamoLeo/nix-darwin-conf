# Repository Guidelines

## プロジェクト構成とモジュール整理
-    `flake.nix` はエントリーポイントであり、
     `modules/host-users.nix` にあるホスト設定を
     常に最新に保つこと。
-    `home/` 配下はユーザ設定で、
     `default.nix` が `shell.nix` や `core.nix`
     などのモジュールを読み込む。
-    `modules/` はシステム全体の制御用で、
     `apps.nix` が Homebrew と Nix のアプリを、
     `system.nix` が macOS 機能を調整する。
-    `scripts/` の `darwin_set_proxy.py` は
     唯一のスクリプトなので、
     冪等性を崩さないように保守する。

## ビルド・テスト・開発コマンド
-    `just darwin` は
     `.#darwinConfigurations.<hostname>.system`
     をビルドして `darwin-rebuild switch`
     を実行する。変更後は必ず走らせる。
-    `just darwin-debug` は詳細ログを追加し、
     評価や適用失敗の調査に使う。
-    `just up` でフレーク入力を更新し、
     併せて `flake.lock` の差分を確認する。
-    `just fmt` は `nix fmt` を呼び出し、
     すべての `*.nix` を整形する。
-    `just clean` と `just gc` で不要な
     世代やストアを整理し、
     成功したデプロイ後に実行する。

## コーディング規約と命名
-    Nix の属性集合は二スペースで
     インデントし、末尾にカンマを置く。
-    オプションは可能な範囲で
     アルファベット順に並べ、
     既存ファイルのパターンに合わせる。
-    `programs.starship` のように
     説明的な属性名を使い、
     省略形は避ける。
-    コミット前に `nix fmt` を実行し、
     指摘をすべて解消する。

## テスト指針
-    自動テストは無いため、
     `just darwin` がエラー無く
     完走することが最低条件。
-    `home/` を更新した際は
     `./result/sw/bin/darwin-rebuild switch`
     `--flake .#<hostname>` を手動で実行する。
-    危険な変更は
     `nix build .#darwinConfigurations.<hostname>.system`
     `--show-trace` でドライラン検証する。
-    目視確認が必要な場合は
     Dock 変更などの結果を
     PR 説明に記録する。

## コミットとプルリクの指針
-    コミットは
     `feat:` や `refactor:` などの
     Conventional Commits を採用する。
-    PR では目的、影響するモジュール、
     関連 Issue を簡潔にまとめる。
-    障害対応時は適用ログや
     コマンド出力を添付して共有する。
-    `flake.lock` の更新や
     シンボリックリンクの生成は
     意図的か確認し、レビューを依頼する。

## セキュリティと構成上の注意
-    `Justfile` の `hostname` は
     運用環境に合わせて更新し、
     デモ用設定で実行しない。
-    `darwin_set_proxy.py` は
     必要なときだけ有効化し、
     ビルド後は環境変数を戻す。

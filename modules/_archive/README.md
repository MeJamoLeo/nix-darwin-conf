# _archive — 退役トピック置き場

無効化の唯一の正規手順：トピックのディレクトリをここへ移し、profile の import を消す。
復帰はその逆（ディレクトリを戻して profile に import 1行）。
「import をコメントアウトしてファイル温存」等のばらばらな無効化はしない。

戻す見込みがほぼ無いものは archive せず**削除**する（git 履歴からいつでも発掘できる。
例：cmux は代替の Ghostty + herdr が定着したため 2026-07-16 に削除）。

## 現在の住人

- **courses/cs3339, courses/cs3354** — 2026 春学期の科目（学期終了につき退役 2026-07-16）。
  course モジュールは学期単位のライフサイクル：学期が終わったらここへ、
  次の学期が無事始まったら削除してよい。新学期は modules/courses/<code>/ を足すだけ。
- **wezterm/** — Ghostty + herdr へ移行（2026-07）に伴い退役 2026-07-16。
  Ghostty 運用が安定したら削除してよい。
- **aerospace/** — WM を OmniWM へ置き換えたため退役 2026-09-09（移行自体は 2026-08-30、
  約10日の並走を経て実体を撤去）。tanegashima / ogasawara の両機で `.app` / brew cask /
  tap / launchd / `~/.aerospace.toml` の不在を実測確認済み。残骸（`~/Library/Logs/
  aerospace-grid.log` と `~/Library/Preferences/bobko.aerospace.plist`、いずれも 2026-02 で
  更新停止）も削除した。**OmniWM 運用が安定したら削除してよい**（wezterm と同じ扱い）。
  復帰手順：`git mv modules/_archive/aerospace modules/apps/aerospace` → profile の
  `../modules/apps/omniwm/home.nix` を `../modules/apps/aerospace/home.nix` に差し替え →
  `brew install --cask aerospace`（nixpkgs 版を使うなら不要）。
  ⚠ 戻すと OmniWM 側の資産を失う：`modules/apps/omniwm/settings.nix` の差分9件、
  内蔵 borders、`omniwmctl` による IPC 連携。逆に AeroSpace にしか無いのは
  **任意コマンドを叩くホットキー**（alt-g → cp-go-launch など。OmniWM は 169 の
  固定コマンド ID しか持たず exec を表現できない。詳細は
  modules/custom/cp/tools/home.nix の該当コメント）。
- **neru/** — 常用しなかったため退役 2026-07-29。
  復帰手順：`git mv modules/_archive/neru modules/apps/neru` → profile の
  `home-manager.users.<name>.imports` に `../modules/apps/neru/home.nix` と
  `neru.homeManagerModules.default` を戻し、関数引数に `neru,` を戻す。
  flake input `neru` と overlay `inputs.neru.overlays.default` は残してあるので
  再導入時に追加で触る必要はない。config には `"Cmd+Shift+C" = "__disabled__"` を
  焼き込んであるので、デフォルトの Cmd+Shift+C（recursive_grid）に占領されない。

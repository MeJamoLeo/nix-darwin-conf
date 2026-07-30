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
- **neru/** — 常用しなかったため退役 2026-07-29。
  復帰手順：`git mv modules/_archive/neru modules/apps/neru` → profile の
  `home-manager.users.<name>.imports` に `../modules/apps/neru/home.nix` と
  `neru.homeManagerModules.default` を戻し、関数引数に `neru,` を戻す。
  flake input `neru` と overlay `inputs.neru.overlays.default` は残してあるので
  再導入時に追加で触る必要はない。config には `"Cmd+Shift+C" = "__disabled__"` を
  焼き込んであるので、デフォルトの Cmd+Shift+C（recursive_grid）に占領されない。

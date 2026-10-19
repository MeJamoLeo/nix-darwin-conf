---
name: viz
description: 説明・概念を「スクロールで状態が連続的に変わる全画面の図」として HTML に書き出し、ブラウザで開く。Claude は JSON（要素＋ステップごとの差分キーフレーム）だけを書き、同梱のエンジンが補間と描画を担う。アルゴリズムの実行過程・データ構造の変化・プロトコルの流れ・関数のパラメータ変化など「状態の遷移」を見せる図解向け。**明示的に頼まれたときだけ使う**：Triggers on "/viz", "図にして", "図解して", "可視化して", "visualize this", "アニメーションで見せて"。頼まれていないのに生成しない。
---

# viz — スクロールで動く図解

**図が主役、文は脇役。** 全画面の SVG 図を、スクロール量に応じてステップ間で連続的に補間する（途中で止めてよい・スナップしない）。各ステップに1〜2文のキャプションが付く。

## 手順

1. **ステップ表を頭の中で切る。** 何を、どの粒度で見せるか。**粒度は細かく**——1ステップ＝1つの変化（1行進む・1つ動く・1つ色が変わる）。まとめて変えたくなったら分ける。重い変化（大きな移動・区間の消去）は `len` を 1.5〜2 にしてスクロール距離を伸ばす。
2. **spec を書く**：`~/.cache/viz/YYYY-MM-DD-<slug>.json`（下の仕様。迷ったら `examples/binary-search.json` を雛形にする）。
3. **ビルドして撮る**：
   ```bash
   python3 ~/.claude/skills/viz/build.py ~/.cache/viz/<file>.json --shot 1,<中間>,<最後>
   ```
   検証エラーが出たら直して再実行する（未知のプロパティ・存在しない参照・範囲外の index は全部ここで落ちる）。PNG を Read して、**重なり・はみ出し・読めない色**を確認する。1回は必ず見る。
4. **開く**：問題なければ `--open` を付けて再実行（または `open <html>`）。
5. **端末への報告は最小**：HTML のパスと一行の要約だけ。説明本文を会話に二重に書かない（説明の正史は HTML のキャプション）。

「残して」「共有したい」「URL ちょうだい」と言われたときだけ、出来た HTML を `Artifact` ツールで公開する（`file_path` に HTML、`icon` は `chart` など）。ページは外部依存ゼロ・ダークモード対応・`<title>` 済みなのでそのまま出せる。

## spec 仕様

```jsonc
{
  "title": "表示タイトル", "slug": "kebab-case",
  "width": 1000, "height": 560,      // viewBox。画面に合わせて拡縮される
  "ease": "smooth",                  // smooth（各ステップ付近で変化が緩む）| linear
  "elements": [ { "id": "...", "type": "...", ...初期プロパティ } ],
  "steps": [ { "caption": "...", "set": { "<id>": { ...変えるプロパティ } }, "len": 1 } ]
}
```

- **`set` は差分。** 書かなかったプロパティは前のステップの値を引き継ぐ。object 型（`cellFill`・`params`）は1階層マージ。
- **補間**：数値・色・数値配列は連続補間。文字列（`label`・`text`・`values`・`lines`・`fn` など）はステップの中間で切り替わる。
- **ステップ番号は 1 始まり**（`show`/`hide`・`--shot`・画面右上の表示がすべて同じ番号）。
- **共通**：`opacity`、`show: k`（ステップ k でフェードイン）、`hide: k`（ステップ k でフェードアウト）。
- **色**：トークン `fg muted panel line accent ok warn bad hl bg none` か `#hex`。**トークンを使う**（ライト/ダーク両対応になる）。
- 座標系：`box`/`circle`/`text`/`number` は **(x, y) が中心**。`code`/`array`/`plot` は **(x, y) が左上**。

| type | 必須 | 任意（既定値） |
|---|---|---|
| `box` | x y w h | label（`\n` で改行） fill(panel) stroke(line) strokeWidth rx(8) labelSize(18) labelColor(fg) dash |
| `circle` | x y r | label fill stroke strokeWidth labelSize labelColor dash |
| `text` | x y text | size(18) color(fg) align(middle\|start\|end) weight |
| `number` | x y value | decimals(0) prefix suffix size(22) color align weight — **value が連続的に増減する** |
| `arrow` | from/to か x1 y1 x2 y2 | color(muted) width(2) bend(0, 正負で曲がる向き) gap(4) head(true) dash label。from/to は要素 id（形の縁に吸着し、相手が動けば追従）か `"arr:3"`（配列の3番目のセル） |
| `code` | x y lines | hl（実行中の行, 1始まり, 0で非表示） size(15) w hlColor(hl) lineNumbers(true) title。**hl は連続移動する** |
| `array` | x y values | cell(48) label cellFill `{"元のindex": 色}` order showIndex(true) indexBase(0) size。**order**（各位置に置く元の index の並び）を変えるとセルが弧を描いて入れ替わる。values の長さは固定 |
| `pointer` | array index | label side(top\|bottom) color(accent) dy。index は連続的にスライドする |
| `plot` | x y w h xr yr | grid(true) ticks(5) xlabel ylabel color。**xr/yr を変えると軸ごとズーム/パン** |
| `curve` | plot, fn か points | fn は x の JS 式（`Math.` 不要: `"a*sin(x)"`）、params `{"a":1}`（連続補間→曲線が変形） reveal(1, 0→1 で左から描かれる) color width dash samples |
| `dot` | plot px py | r(6) color label guides（軸への破線） |

## 図の作り方の勘所

- **1画面に要素を詰めすぎない。** 全画面 1000×560 に、主役1つ（配列・図・グラフ）＋補助1〜2つ（コード・数値）が目安。
- **動く量で注意を引く。** 変化しない要素は動かさない。強調は `cellFill`・`fill` の色変化と `opacity` の減衰（用済みは 0.3 程度に落とす）で。
- **状態変数は `number` で見せる。** `lo = 5` のような値を、矢印や配列の動きと同じステップで変える。
- **キャプションは「いま何が起きたか」を1〜2文で。** `` `code` `` と `**強調**` が使える。長い説明が要るなら、そこはステップを分けるべきサイン。
- 最初のステップは「問題の提示」、最後は「まとめ（なぜそうなるか）」にする。

## やらないこと

- 頼まれていないのに生成・`open` しない。
- エンジン（`template.html`）を毎回書き換えない。表現が足りないときは、エンジンへの部品追加を**提案**する（この skill は nix-darwin-conf 管理）。
- spec をプロジェクトのディレクトリや vault に置かない（`~/.cache/viz/` だけ）。

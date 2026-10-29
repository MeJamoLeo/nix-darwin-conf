---
name: viz
description: 説明・概念を「ステップごとに状態が変わる図」にする。出力は3パターン：①会話の中に Mermaid の図を並べる Markdown 版（既定・ファイルを作らない）②スクロールで連続的に動く全画面の HTML 版（ブラウザで開く）③ターミナル向けの ASCII 版（spec からコマ送りの文字図を出す）。アルゴリズムの実行過程・データ構造の変化・プロトコルの流れ・関数のパラメータ変化など「状態の遷移」を見せる図解向け。**明示的に頼まれたときだけ使う**：Triggers on "/viz", "図にして", "図解して", "可視化して", "visualize this", "アニメーションで見せて", "ASCII で図にして", "ターミナルで見せて"。頼まれていないのに生成しない。数式を見せたいだけなら使わない（返信に `$...$` で直接書く）。
---

# viz — ステップで動く図解

**図が主役、文は脇役。** 1ステップ＝1つの変化。各ステップに1〜2文のキャプションが付く。

## どのパターンで出すか（最初に決める）

| 言われ方・状況 | パターン | 出力 |
|---|---|---|
| 「図にして」だけ（既定） | **Markdown** | 返信の中に Mermaid の図をステップ順に並べる。ファイルを作らない |
| 「HTML で」「アニメーション」「じっくり」「共有したい」、連続的な動き（グラフの変形・要素の移動）が主役のとき | **HTML** | `~/.cache/viz/*.html` を書き出してブラウザで開く |
| 「ターミナルで」「ASCII で」 | **ASCII** | spec から `build.py --ascii` で文字図を出し、返信にコードブロックで貼る |
| 数式を見せたいだけ | **viz を使わない** | 返信に `$...$`・`$$...$$`・`\( \)`・`\[ \]`・`` ```math `` で直接書く |

見る場所の事実（2026-10-28 確認）：
- **Orca の会話ビュー**（cmd+shift+J）は Markdown・表・Mermaid を描く。数式は Orca 1.4.243 以降で描く（`$`・`$$`・`\( \)`・`\[ \]`・`` ```math ``。`` ```latex `` と `` ```katex `` はコードのまま）。
- 同じ会話ビューの等幅フォントは**全角が2マスちょうどにならない**ので、日本語入りの ASCII の枠はずれる。会話ビューで見ている相手には ASCII ではなく Markdown 版を出す。
- 普通のターミナル（Ghostty など）では全角は2マスで、ASCII 版の枠は揃う。

## Markdown 版（会話ビュー向け・既定）

ファイルも spec も作らない。返信そのものが図になる。

1. ステップ表を切る。ただし各ステップが図1枚まるごとになるので、**3〜6ステップ**に絞る。
2. 全ステップで**同じ骨格の Mermaid**（ノードと辺の並び）を使い、変わる所だけを `class` で塗り替える。骨格が変わると Mermaid の自動配置が動いて、何が変わったか追えなくなる。
3. 形式：
   ````markdown
   **1/4 ステップの見出し**

   ```mermaid
   flowchart LR
     classDef ok stroke:#3fb950,stroke-width:3px
     classDef bad stroke:#f85149,stroke-width:3px
     classDef dim opacity:0.35
     a[あなた] --> z[Zen] -->|柵 2| yt[(YouTube)]
     class z ok
   ```

   1〜2文のキャプション。数式は $O(n \log n)$ のように**キャプションに**書く。
   ````
4. 守ること：
   - **Mermaid のラベルの中に数式を書かない**（`$$...$$` は生のまま出た。1.4.242 で確認。1.4.243 以降は未確認なので避ける）。
   - `$HOME/$USER` のようにドルが並ぶ文は数式と誤認されるので、コード（`` ` ``）で囲む。
   - 色は `classDef` の stroke（枠線）で付ける。fill を濃くすると暗いテーマで文字が読めなくなる。
   - ノード id は ASCII、表示ラベルは日本語でよい。

## ASCII 版（ターミナル向け）

HTML 版と**同じ spec** を使う（下の「spec 仕様」）。

```bash
python3 ~/.claude/skills/viz/build.py ~/.cache/viz/<file>.json --ascii [--cols 100]
```

- 全ステップの到達状態をコマとして順に stdout に出す（補間はしない）。出力を返信に `` ``` `` で囲んでそのまま貼る。HTML は書き出さない。
- 色は線種で表す：`opacity < 0.5` → 点線（┄ ┆）、`strokeWidth ≥ 3`（箱）・`width ≥ 4`（矢印）→ 太線（━ ┃）、`cellFill` → セルの下の印（`^` hl/accent・`✓` ok・`×` bad・`!` warn・`·` muted/line）。
- 箱は、ラベルが入りきらなければ左右に広げる。縦に入らない複数行ラベルは1行にまとめる。
- `curve` は点（•）で描く。`fn` は Python で評価するので、JS 固有の構文（三項演算子など）は使えない。
- 1回は出力を見て、重なり・はみ出しを確認する。座標系は HTML と同じなので、詰まっていたら spec の配置を広げるか `--cols` を上げる。

## HTML 版

### 手順

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
- 数式だけのために viz を使わない（会話ビューがそのまま描く）。
- エンジン（`template.html`）を毎回書き換えない。表現が足りないときは、エンジンへの部品追加を**提案**する（この skill は nix-darwin-conf 管理）。
- spec をプロジェクトのディレクトリや vault に置かない（`~/.cache/viz/` だけ）。

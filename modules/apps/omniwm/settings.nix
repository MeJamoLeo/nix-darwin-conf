# ⚠ このファイルは modules/apps/omniwm/home.nix の `settings` の実体。
#
#   ★ 2026-09-05 に**全面リセット**した。それ以前の版（AeroSpace 由来の 3×3 グリッド・
#     9ワークスペース宣言・appRules 13件・独自キー配置）は git 履歴にある
#     （最後は 87c9e70 の親）。混ざったコンテキストを一度捨てて、
#     **OmniWM の素の既定 + 明示的な差分だけ**という形に組み直したもの。
#
#   ★ 2026-09-08 に**キーバインドの文法を niri 本家へ揃え直した**（下の §文法）。
#     それまでは niri の `Mod+Ctrl`（動かす）と `Mod+Shift`（モニタ）を入れ替えて
#     使っていたが、その入れ替えの副作用で
#       ①モニタ間の窓移動（moveWindowToMonitor.* 4件）が未割当のまま残り、
#       ②ワークスペースへの絶対送り（moveColumnToWorkspace.* 9件）も未割当だった。
#     niri のスロットを別の用途が占拠していたのが原因なので、文法ごと戻した。
#
#   ★ 既定値は推測ではなく**実測で採取**した：live の settings.toml を退避 →
#     OmniWM を再起動 → 生成された素の settings.toml を採取、という手順。
#     そのとき判明したこと：
#       - appRules 13件（Chrome / Safari / Zed / Discord 等の最小サイズ）は
#         **OmniWM の組み込み既定**。以前の宣言は既定の書き写しだった。
#       - workspaces の既定は **9件**。公式 settings-reference が
#         「`1`–`5` と `8`–`9` が main、`6`（❤️）と `7`（🚀）が secondary」と明記し、
#         `omniwmctl query workspaces` の実測も 1,2,3,4,5,8,9,6,7 の順で一致する。
#         ⚠ ただし **settings.toml には 7件しか永続化されない**（8 と 9 が書かれない）。
#         ファイルとランタイムが食い違う。採取直後にファイルだけ見て「既定は7件」と
#         誤読したが、8/9 は動的生成ではなく既定の一部である。
#       - borders の既定は enabled = true / width = 5.0 / シアン。以前 JankyBorders に
#         逃がしていた分はここへ戻した（home.nix の該当節を参照）。
#       - `general.ipcEnabled` の既定は **false**。omniwmctl が全滅するので下で上書きする。
#
# ★ ここに**書いてはいけない**もの（merge-settings.nu が live 側を残す層）：
#     monitorBarOverrides / monitorDwindleOverrides / monitorGapOverrides /
#     monitorNiriOverrides / monitorOrientationOverrides / monitorRoutingOverrides /
#     [routing] mode
#   これらは `monitorDisplayUUID` がキー＝**物理ディスプレイと机の記述**で、
#   ogasawara と tanegashima で必ず食い違う。実機の GUI（Settings > Monitors）が正。
#
# ★ `schemaVersion` も書かない。OmniWM がスキーマ移行で自分で上げるので、
#   宣言で固定すると移行を潰す。
#
# 🔴 **配列は全件書くか、一切書かないかの二択。** merge-settings.nu の deep-merge は
#   record にしか再帰せず、配列はテンプレート側が丸ごと勝つ。だから `hotkeys` は
#   **191件**を全件書いている（減らすと残りが Unassigned に飛ぶ）。
#   ⚠ 「169件」は 0.6.4 時点の数。0.7.6 で 191 まで増えている。
#   2026-10-26 の実測で `toggleFloatingFocus` が宣言から**抜けていた**
#   （live には在り Unassigned）。ID が増えたら宣言も足すこと —— 抜けた ID は
#   OmniWM が Unassigned で書き戻すので壊れないが、nix からは永久に割り当て不能になる。
#   照合コマンド：live の `[[hotkeys]]` の id 集合と本ファイルの `(hk "…"` を comm する。逆に `workspaces` と
#   `appRules` は**一切書かない**＝ live 側（＝ OmniWM の既定）がそのまま残る。
#
# ──────────────────────────────────────────────────────────────────────────
#  §文法 — 修飾キーの段が「何をするか」を決める（niri 本家の binds に一致）
#
#    Option                見る・行く            niri `Mod`
#    Control+Option        **動かす**            niri `Mod+Ctrl`
#    Option+Shift          **送る**・モニタ      niri `Mod+Shift`
#    Control+Option+Shift  **モニタへ送る**      niri `Mod+Ctrl+Shift`
#
#  同じ H/J/K/L が段ごとに「見る → 動かす → 送る → モニタへ送る」と粒度を上げる。
#  niri のドキュメント（resources/default-config.kdl）をそのまま読み替えられる。
#
#  ★ ワークスペースは**数字列**（niri 本家の `Mod+1..9` と同じ）。段だけで粒度が変わる：
#      Option+N          ws N へ行く          niri `Mod+N`
#      Option+Shift+N    窓1枚を ws N へ送る  （OmniWM 固有。niri に相当なし）
#      Control+Option+N  カラムを ws N へ送る niri `Mod+Ctrl+N`
#    ソースで確認済み：`ActionCatalog.swift` の
#    `case let .switchWorkspace(idx): "Switch to Workspace \(idx + 1)"`。
#    つまり `switchWorkspace.0` は **ws「1」**であって「一覧の先頭」ではない
#    （ogasawara の実測では一覧の先頭は ws「4」なので、ここは間違えやすい）。
#
#    ⚠ 2026-09-08 に一度**左手 3×3（Q W E / A S D / Z X C）**へ載せ替えたが、使わない
#      と判断して同日撤回した。Q/W/E/A/S/D/Z/X は Unassigned のまま空けてある。
#      `focusColumn.0..8` はその玉突きで Control+Option+1..9 → **Control+Option+Shift+1..9**
#      へ退避した（意味の段としては浮くが、既存機能を消さないため残している。
#      要らなければ9件を Unassigned にすれば Ctrl+Opt+Shift の数字列がまるごと空く）。
#
#  ⚠ niri にあって OmniWM で**再現できない**もの（169 ID を全走査して不在を確認）：
#    - `focus-monitor-{left,right,up,down}`（方向指定）
#        OmniWM は Next / Previous / Last の3つだけ。
#        🔴 **→ 差分19 で改訂。** ここに書いていた「2画面なら方向と一致する」は
#          **誤り**だった。2026-10-27 の実測で next / prev が走る順は
#          **display の index 順**（isMain が先）で、**x 座標の順ではない**と判明。
#          当時の構成では index 順が位置順の逆で、Previous が右・Next が左に動いて
#          いた（＝ H で右・L で左）。割当は差分19で入れ替えた。
#          `Option+Shift+J/K` は上下に対応する動作が無いので空けたまま。
#    - `close-window`（`Mod+Q`）
#        enum に `closeFocusedWindow` は在るが、0.6.4 の hotkey ID 169件には
#        **露出していない**（live settings.toml と突き合わせ済み）。バインドできない。
#    - `spawn`（`Mod+T` / `Mod+D`）— ホットキーに exec が無い（既知。watch --exec で代替）
#    - `Mod+BracketLeft/Right`（consume-or-expel の左右版）— hotkey ID が無い
#    - `move-workspace-up/down`（ワークスペースの並べ替え）— 相当する ID が無い
#
# ──────────────────────────────────────────────────────────────────────────
#  素の既定からの差分。増やすときはここに追記すること。
#
#   1. general.ipcEnabled = true
#        既定 false。false だと ~/Library/Application Support/com.barut.OmniWM/ipc.sock
#        （0.7.5 で ~/Library/Caches/ から移った）が
#        開かず omniwmctl（query / watch / rule）が全滅する。
#
#   2. 方向キーを矢印から H/J/K/L へ（既定で矢印だった12件すべて）
#        focus.{left,down,up,right}      Option+矢印 → Option+H/J/K/L
#          🔴 **→ 差分18 で矢印へ戻した**（Secure Input 対策。hjkl は Karabiner 経由）
#        moveColumn.{left,right}         → Control+Option+H/L   （niri `Mod+Ctrl+H/L`）
#        moveWindowDown / moveWindowUp   → Control+Option+J/K   （niri `Mod+Ctrl+J/K`）
#        moveWindowToMonitor.{左下上右}  → Control+Option+Shift+H/J/K/L
#      ※ 🔴 **→ 差分14/18 で改訂。** 当時は「矢印は moveWorkspaceToMonitor.* だけが
#        使う（差分9）」「`move.{left,down,up,right}` は Unassigned」と書いたが、
#        現在は矢印段を3つ使っている：
#          Option+矢印              focus.*                （差分18）
#          Control+Option+矢印      move.*                 （差分14）
#          Control+Option+Shift+矢印 moveWorkspaceToMonitor.*（差分9・据え置き）
#
#   3. toggleWorkspaceLayout = Unassigned
#        既定は Option+Shift+L だが、focusMonitorNext と衝突するため外した。
#        CLI の `omniwmctl command toggle-workspace-layout` は使える。
#
#   4. ワークスペースの相対切替を Option+U / Option+I に割り当て
#        switchWorkspace.next      未割当 → Option+U   （niri `Mod+U` = down 相当）
#        switchWorkspace.previous  未割当 → Option+I   （niri `Mod+I` = up   相当）
#        ⚠ 末尾を越えたときに createDynamicWorkspace を踏んでワークスペースが
#          増えるかは**未確認**。増殖の実測は相対「移動」で踏んだ話で、
#          フォーカス切替では確かめていない。連打して
#          `omniwmctl query workspaces` が9件を超えないか見ること。
#
#   5. 数字列3段でワークスペースの粒度を表す（niri `Mod+N` / `Mod+Ctrl+N` に一致）
#        switchWorkspace.0..8       Option+1..9         （既定のまま）
#        moveToWorkspace.0..8       Option+Shift+1..9   （既定のまま）
#        moveColumnToWorkspace.0..8 未割当 → **Control+Option+1..9**（niri `Mod+Ctrl+1..9`）
#        focusColumn.0..8           Control+Option+1..9 → Control+Option+Shift+1..9（玉突き）
#        centerColumn               Option+C            （既定のまま。niri `Mod+C`）
#        centerVisibleColumns       未割当 → **Control+Option+C**（niri `Mod+Ctrl+C`）
#      ★ 差分の芯はここ。**カラムを ws N へ直接送る口**が今まで存在しなかった
#        （moveColumnToWorkspace.0..8 が9件とも未割当だった）。相対送りの U/I しか
#        無かったので、遠い ws へ送るのに連打が要った。
#      ⚠ Control+Option+Shift+U/I は当時**意図的に空けてあった**が、
#        🔴 **→ 差分15 で埋めた**（moveColumn.down = U / moveColumn.up = I）。
#        moveColumnToIndex.1..9 を置きたくなったら上の Ctrl+Opt+Shift 数字列へ。
#
#   6. モニタ操作を Option+Shift 段へ（niri `Mod+Shift` = monitor に合わせる）
#        focusMonitorNext      Control+Option+Tab       → Option+Shift+L
#        focusMonitorPrevious  Control+Option+Shift+Tab → Option+Shift+H
#          🔴 **→ 差分19 でこの2つを入れ替えた**（Next が左・Previous が右に動く
#            ことが実測で判明したため。この行の割当は現在のコードと逆）
#        focusMonitorLast      Control+Option+Grave     → Option+Shift+Grave
#        workspaceBackAndForth Control+Option+Tab       → Option+Shift+Tab（据え置き）
#      Tab の粒度：
#        Option+Tab        直前の**窓**            (focusPrevious)
#        Option+Shift+Tab  直前の**ワークスペース** (workspaceBackAndForth)
#
#   7. カラムへの窓の出し入れを niri の定位置へ（Option+Comma / Option+Period）
#        consumeWindowIntoColumn  未割当        → Option+Comma
#        expelWindowFromColumn    未割当        → Option+Period
#        cycleSizeForward         Option+Period → Option+R          （niri `Mod+R`）
#        cycleSizeBackward        Option+Comma  → Control+Option+R  （玉突き）
#        resetWindowSecondarySpan Control+Option+R → Unassigned     （玉突きの玉突き）
#        必要なら `omniwmctl command reset-window-secondary-span` で叩ける。
#
#   8. Option+一文字を3つ埋めた
#        toggleOverview               Option+Shift+O → Option+O （niri `Mod+O`）
#        toggleFocusedWindowFloating  未割当         → Option+V （niri `Mod+V`）
#        toggleColumnTabbed           既定のまま     → Option+T
#          ※ niri は `Mod+W` だが、W は 3×3 の ws2 に取られているので T のまま。
#      ⚠ Overview は**画面収録の権限**が要る（アクセシビリティ・入力監視は必須、
#        画面収録は Overview 用に任意）。
#
#   9. ワークスペース／モニタへの「送り」を3段に整理
#        moveWindowToWorkspace{Down,Up}   → Option+Shift+U / I            窓1枚を上下の ws へ
#        moveColumnToWorkspace{Down,Up}   → Control+Option+U / I          カラムを上下の ws へ
#                                            （niri `Mod+Ctrl+U/I` に一致）
#        moveColumnToWorkspace.0..8       → Control+Option+{QWE/ASD/ZXC}  カラムを ws N へ
#                                            （niri `Mod+Ctrl+1..9` に一致）
#        moveWindowToMonitor.{左下上右}   → Control+Option+Shift+H/J/K/L  窓をモニタへ
#        moveWorkspaceToMonitor.{左右上下} → Control+Option+Shift+矢印     ws ごとモニタへ
#      ★ moveWorkspaceToMonitor.* は `ipcCommandName` が **nil**＝
#        **omniwmctl から呼べない唯一の系**。キーを当てないと到達不能なので割り当てた。
#      ⚠ モニタへの送りは**折り返さない**（方向指定のみで、端では無反応）。
#        AeroSpace の `--wrap-around` に相当するものが無い。
#
#  10. focus.followsWindowToMonitor = true（キーは差分9のまま・設定1行のみ）
#
#      niri の `Mod+Ctrl+U/I`（move-column-to-workspace）は **既定でフォーカスが
#      追従する**（niri-config/src/binds.rs: `property(name="focus"), default = true`）。
#      OmniWM でこれに相当するのが本設定 ── 名前は "Monitor" だが upstream PR #489
#      （issue #488、2026-07-17 merge、v0.6.4 に同梱）で**ワークスペース間の移動も
#      この設定を見る**ようになった。つまり true にするだけで
#      `Control+Option+U/I`（カラム送り）が niri の既定挙動と一致する。
#
#      実測（v0.6.4 / true にして）:
#        move-column-to-workspace down/up  → **追従する** ✅（niri と同じ）
#        move-to-workspace down/up（窓単位）→ **追従しない** ❌
#      窓単位は upstream の取りこぼし ── #488 の本文は `moveWindowToAdjacentWorkspace`
#      も直す前提なのに、0.6.4 ではカラム版しか追従しない。niri の既定バインドに
#      窓単位の相対送りは無いので niri 準拠度には影響しないが、issue を出す価値は
#      ある（v0.6.8 で直っている可能性があるので、版を上げてから再測すること。
#      現在 v0.6.4 / 最新 v0.6.8）。
#
#      ※ 一度「追従の有無でキー段を分ける」案（Option+Shift+U/I をカラム送りに
#        入れ替える）を実装しかけたが、niri 文法を崩すため**同日撤回**した。
#        追従して送りたいときは `Control+Option+U/I` を使うこと。
#
#  以下は 0.7.4 への更新（2026-10-02）で足した分。
#
#  11. closeFocusedWindow = Option+Q
#        0.6.4 では hotkey ID に露出しておらずバインド不可だった（上の「再現できない
#        もの」に書いてある通り）。0.7.4 で露出したので niri 本家の `Mod+Q` に揃えた。
#
#  12. niri.defaultContainerPrimarySpan = 1/3
#        既定 0.5。新しい列が最初から 1/3 幅で出る（2026-10-04 に 2/3 から変更）。
#        ⚠ `visibleContainerCount` はこの値がある限り死んでいる（下のコメント参照）。
#
#  13. gestures.overviewGestureEnabled = true
#        既定 false。3本指は列スクロールに使っているので Overview は既定の4本指のまま。
#
#  以下は縦向きディスプレイ対応（2026-10-26）。
#
#  ★ 前提：**OmniWM は縦長ディスプレイを自動検出して niri の軸を 90° 回す。**
#    `Monitor.autoOrientation` が `frame.width >= frame.height ? .horizontal : .vertical`
#    で、`monitorOrientationOverrides` が無ければこれが使われる
#    （`MonitorConfigurationSettings.effectiveOrientation`）。縦向きではコンテナが
#    上下に積まれ、コンテナ内の窓が左右に並ぶ。コンテナ index は**下から上**へ増える
#    （`Direction.primaryStep`: vertical は `.up` = +1）。
#
#  ★ 問題：**縦向きだとコンテナを並べ替えるキーが1つも無かった。**
#    `Direction.primaryStep(for:)` は軸外の方向に nil を返すので、vertical では
#    `moveColumn.left/right`（Control+Option+H/L）が丸ごと無反応になる。そして
#    `moveColumn.up/down` と `move.*` 4件がどちらも Unassigned だったため逃げ場が無かった。
#    旧コメントの「move.* は moveColumn / moveWindowDown|Up と重複する」は
#    **横向き前提でだけ正しい**判断だった。
#
#  14. move.{left,down,up,right} = Control+Option+矢印
#        move.* は **191 ID の中で唯一、両軸とも実行時の orientation を見る**系。
#        `NiriLayoutHandler+WindowMovement.swift:64` の
#        `let movesAcrossContainers = direction.primaryStep(for: ctx.orientation) != nil`
#        で主軸／副軸を振り分ける＝向きが変わっても「見えてる方向」に動く。
#        公式 docs（guides/keyboard-shortcuts）も
#        「Vertical orientation rotates those roles」と明記している。
#        ⚠ niri に相当アクションは無い（niri に vertical orientation が無いため）。
#          だから niri 準拠の hjkl 段（下の moveColumn + moveWindowDown|Up）は
#          **一切触っていない**。move.* は別家族として矢印に同居させる。
#        ⚠ `niri.moveWindowStacksIntoColumn` の既定は true ＝主軸の移動は
#          「隣のコンテナに吸わせる」。false にすると「隣と入れ替える」になるが、
#          それは moveColumn 側の仕事なので既定のまま触らない。
#        🔴 **OmniWM 既定の Option+Shift+矢印は採らない。** `Opt+Shift+←/→` は
#          macOS の「単語単位の選択」、`Opt+Shift+↑/↓` は「行頭/行末まで選択」で、
#          Carbon のグローバルホットキーはイベントを食うので全アプリのテキスト欄が
#          壊れる。`Opt+←/→`（単語単位カーソル移動）も同じ理由で使えない。
#          ＝**Option 単独段と Option+Shift 段に矢印は置けない。** 残るのは
#          Control+Option 段と Control+Option+Shift 段で、後者は
#          moveWorkspaceToMonitor.* が既に占有（差分9・他に到達経路が無い系）。
#          よって move.* は Control+Option+矢印に置く。
#
#  15. moveColumn.up/down = Control+Option+Shift+I / U
#        縦向きでのコンテナ並べ替え。横向きでは primaryStep が nil なので無反応
#        （副作用ゼロ）。Control+Option+矢印は差分14の move.* に明け渡したので、
#        §文法が「意図的に空けてある」と書いていた Control+Option+Shift+U/I へ置いた
#        （U=down / I=up は Option+U/I・Control+Option+U/I の上下向きと一致させている）。
#        ⚠ 公式 docs は "Move Container Up / Down" を `Dwindle` と書いているが、
#          `CommandHandler.moveContainer` は `.niri` でも
#          `niriLayoutHandler.moveColumn(direction:)` に流すので Niri 縦向きでも効く。
#        ⚠ moveColumnToIndex.1-9 の予約先はここではなくなった。要るなら
#          Control+Option+Shift の数字列（今は focusColumn.0-8）と取り合うこと。
#
#  16. cycleWindowSecondarySpanForward = Control+Option+Shift+R
#        niri `Mod+Ctrl+Shift+R`（switch-preset-window-height）の定位置。既定は未割当。
#        ⚠ Command Palette の Windows モードのローカル shortcut（Remove Mark）と
#          同じキーだが、docs 通りローカル側が global に譲る（ボタンは残る）。
#        backward は niri に相当が無いので Unassigned のまま。
#
#  17. toggleFloatingFocus = Option+Shift+V
#        niri `Mod+Shift+V`（switch-focus-between-floating-and-tiling）。
#        0.7.x で増えた ID で、本ファイルの宣言から抜け落ちていた（上の🔴参照）。
#
#  18. focus.{left,down,up,right} = Option+矢印（Karabiner と対で成立する）
#        2026-10-27 の実測：Secure Input が ON の間、`Option+O`（Option+英字）は
#        効かず `Option+←`（Option+矢印）は効いた。上流 #788 の記述どおり。
#        ★ Ghostty は `macos-auto-secure-input = true` が既定でパスワード入力を
#          検出するたび Secure Input を入れるので、これは**日常的に踏んでいる**。
#          **発見時点では割当 89 件中 46 件**（focus 4・ワークスペース 18 を含む）が
#          止まっていた。この差分を当てた後は **97 件中 42 件**——`focus.*` の4件を
#          矢印に逃がした分だけ減り、新たに割り当てた8件は全部 Control 段（安全側）。
#          内訳は数字 18・英字 16・記号 8。
#          ⚠ 数え直すときは live から採る（宣言側を grep するとコメント内の
#            `(hk "…"` を拾って1件多く出る）：
#              python3 -c 'import re,os;t=open(os.path.expanduser("~/.config/omniwm/settings.toml")).read();\
#                rows=[(re.search(r"id = \"([^\"]+)\"",b).group(1), re.search(r"binding = \"([^\"]+)\"",b).group(1)) \
#                for b in re.findall(r"^\[\[hotkeys\]\]\n((?:[a-zA-Z].*\n)+)",t,re.M)];\
#                print(len(rows), len([r for r in rows if r[1]!="Unassigned"]))'
#        対処：hjkl を捨てるのではなく、**Karabiner で Option+HJKL → Option+矢印 に
#        変換し、OmniWM 側を矢印で受ける**（modules/apps/karabiner/home.nix）。
#        指は hjkl のまま／物理矢印も効く／Secure Input でも死なない、を同時に満たす。
#        変換の向きを逆（矢印→hjkl）にすると window server に Option+英字 が届くので
#        **無意味になる**。
#        ⚠ Karabiner のルールは Option **単独段だけ**。Control+Option 段と
#          Option+Shift 段の hjkl は無傷（＝ niri 文法はそのまま）。
#        🔴 代償：macOS の `Option+←/→`（単語移動）と `Option+↑/↓`（段落移動）が
#          全アプリで効かなくなる。OmniWM がグローバルに食うため。
#        ⚠ **数字列（Option+1-9・Option+Shift+1-9 の 18 件）は救えていない。**
#          矢印に相当するキーが無く、Control/Command を足す段は既に埋まっている。
#          ワークスペース切替は Secure Input 中は止まったまま。未解決。
#
#  19. focusMonitorNext / Previous の割当を入れ替えた（hjkl の向きと一致させる）
#        focusMonitorNext      Option+Shift+L → **Option+Shift+H**（左へ）
#        focusMonitorPrevious  Option+Shift+H → **Option+Shift+L**（右へ）
#        2026-10-27 の実測（LG QHD x=-2560 / U32J59x x=0 の2画面）：
#          LG(左) --prev--> U32J59x(右) ／ U32J59x(右) --next--> LG(左)
#          どちらも端で**止まる**（循環しない。prev を2回押しても戻らない）
#        原因＝ next / prev が走る順は **display の index 順**
#        （display:1 = U32J59x = isMain、display:2 = LG）で、**x 座標の順ではない**。
#        この構成では index 順が位置順の逆なので、名前と実際の向きが反転していた。
#        ⚠ **この入れ替えは今の構成に依存する。** モニタを差し替えたり管理対象を
#          3枚にすると index 順が変わって意味が反転しうる。確認手順：
#            omniwmctl query displays --json                # x 座標で左右を見る
#            omniwmctl command focus-monitor prev / next    # どっちに動くか実測
#        ※ Sidecar（AirPlay）はワークスペースが未割当で、この巡回に**入らない**
#          （実測：prev / next を連打しても LG と U32J59x の2つしか通らない）。
#        ※ OmniWM 0.7.6 に方向指定のモニタフォーカスは無い（`focus-monitor` は
#          prev|next|last のみ）。一方 `move-to-monitor` と
#          `swap-workspace-with-monitor` は <left|right|up|down> を取る＝上流の穴。
#          スクリプト化（`switch-workspace anywhere <N>` で代替）も検討したが、
#          実測で単に名前が逆だっただけなので**入れ替えだけで足りた**。
#        🔴 残件：`Option+Shift+文字` なので **Secure Input 中はこのペアは死ぬ**。
#          `Option+Shift+矢印` は4つとも空いているが、そこは macOS の
#          単語/段落単位の選択拡張なので、代償込みの判断が要る。未着手。
#
#  ▼ 縦向きで**やらなかった**こと（判断の記録）
#    - Control+Option+H/J/K/L を move.* に載せ替える案：却下。niri の
#      `Mod+Ctrl+H/J/K/L` = move-column-left / move-window-down / move-window-up /
#      move-column-right にちょうど一致している現状を崩すため。move.* は
#      コンテナに窓が2枚以上あるとき「コンテナごと動く」ではなく「その窓だけ expel」
#      になるので、意味も等価ではない。
#    - **矢印を hjkl の真のエイリアスにする**（niri は `Mod+Left` == `Mod+H` を
#      全段でエイリアスにしている）：**OmniWM 単体では不可能**。
#      `HotkeyTrigger` は `unassigned | chord(KeyBinding) | mouseButton` で
#      `KeyBinding` は単一 keyCode（`HotkeyBinding.swift:216`）。TOML に同じ id を
#      2行書いても `HotkeyBindingRegistry.swift:42` の
#      `uniquingKeysWith: { first, _ in first }` で先着1個に潰れる。
#      同一挙動の別 ID も存在しない。外部リマッパ（Karabiner / kanata で
#      「修飾キー＋矢印 → 同じ修飾キー＋hjkl」）か skhd + omniwmctl が要る。
#      🔴 **→ 2026-10-27 に Karabiner-Elements を導入して解決した**
#      （`modules/apps/karabiner/home.nix`・差分18）。ただしエイリアス化したのは
#      **Option 単独段の hjkl だけ**で、全段のエイリアスにはしていない。
#    - R 段・F 段の niri 不一致（cycleSizeBackward が Control+Option+R で niri は
#      `Mod+Shift+R`／toggleContainerFullPrimarySpan が Option+Shift+F で niri は
#      `Mod+F`／toggleColumnTabbed が Option+T で niri は `Mod+W`）は**手付かず**。
#      どれも既存の割当を動かす玉突きが要るので、追加だけで済む本バッチから外した。
#
#  ★ borders.enabled = true は「差分」ではなく**既定へ戻すための宣言**なので
#    この一覧には入れない（経緯は下の該当コメント）。
# ──────────────────────────────────────────────────────────────────────────
{
  # hotkeys を1行1バインドに畳むヘルパ。Unassigned も全件残すこと（上の🔴）。
  hotkeys = let
    hk = id: binding: {inherit id binding;};
  in [
    (hk "toggleScratchpad.1" "Unassigned")
    (hk "assignFocusedWindowToScratchpad.1" "Unassigned")
    (hk "toggleScratchpad.2" "Unassigned")
    (hk "assignFocusedWindowToScratchpad.2" "Unassigned")
    (hk "toggleScratchpad.3" "Unassigned")
    (hk "assignFocusedWindowToScratchpad.3" "Unassigned")
    (hk "toggleScratchpad.4" "Unassigned")
    (hk "assignFocusedWindowToScratchpad.4" "Unassigned")
    (hk "toggleScratchpad.5" "Unassigned")
    (hk "assignFocusedWindowToScratchpad.5" "Unassigned")
    (hk "toggleScratchpad.6" "Unassigned")
    (hk "assignFocusedWindowToScratchpad.6" "Unassigned")
    (hk "toggleScratchpad.7" "Unassigned")
    (hk "assignFocusedWindowToScratchpad.7" "Unassigned")
    (hk "toggleScratchpad.8" "Unassigned")
    (hk "assignFocusedWindowToScratchpad.8" "Unassigned")
    (hk "toggleScratchpad.9" "Unassigned")
    (hk "assignFocusedWindowToScratchpad.9" "Unassigned")
    (hk "toggleScratchpad.10" "Unassigned")
    (hk "assignFocusedWindowToScratchpad.10" "Unassigned")

    # ── ワークスペース：数字列（niri `Mod+N` に一致） ──
    #    Option         = そこへ行く
    #    Option+Shift   = 窓1枚を送る
    #    Control+Option = カラムごと送る（下の moveColumnToWorkspace.*）
    (hk "switchWorkspace.0" "Option+1")
    (hk "moveToWorkspace.0" "Option+Shift+1")
    (hk "switchWorkspace.1" "Option+2")
    (hk "moveToWorkspace.1" "Option+Shift+2")
    (hk "switchWorkspace.2" "Option+3")
    (hk "moveToWorkspace.2" "Option+Shift+3")
    (hk "switchWorkspace.3" "Option+4")
    (hk "moveToWorkspace.3" "Option+Shift+4")
    (hk "switchWorkspace.4" "Option+5")
    (hk "moveToWorkspace.4" "Option+Shift+5")
    (hk "switchWorkspace.5" "Option+6")
    (hk "moveToWorkspace.5" "Option+Shift+6")
    (hk "switchWorkspace.6" "Option+7")
    (hk "moveToWorkspace.6" "Option+Shift+7")
    (hk "switchWorkspace.7" "Option+8")
    (hk "moveToWorkspace.7" "Option+Shift+8")
    (hk "switchWorkspace.8" "Option+9")
    (hk "moveToWorkspace.8" "Option+Shift+9")

    (hk "workspaceBackAndForth" "Option+Shift+Tab")
    (hk "switchWorkspace.next" "Option+U")
    (hk "switchWorkspace.previous" "Option+I")

    # ── 見る（niri Mod） ──
    # ⚠ 矢印であって hjkl ではない。Karabiner が Option+HJKL をここへ変換する（差分18）。
    #    指は hjkl のまま・物理矢印も効く・Secure Input でも死なない、の3つを同時に取るため。
    (hk "focus.left" "Option+Left Arrow")
    (hk "focus.down" "Option+Down Arrow")
    (hk "focus.up" "Option+Up Arrow")
    (hk "focus.right" "Option+Right Arrow")
    (hk "focusPrevious" "Option+Tab")
    (hk "focusDownOrLeft" "Unassigned")
    (hk "focusUpOrRight" "Unassigned")
    (hk "focusWindowTop" "Unassigned")
    (hk "focusWindowBottom" "Unassigned")
    (hk "focusWindowDownOrTop" "Unassigned")
    (hk "focusWindowUpOrBottom" "Unassigned")
    (hk "focusWindowOrWorkspaceDown" "Unassigned")
    (hk "focusWindowOrWorkspaceUp" "Unassigned")
    (hk "centerColumn" "Option+C")
    (hk "centerVisibleColumns" "Control+Option+C")

    # ── 送る（ワークスペースへ） ──
    (hk "moveWindowToWorkspaceUp" "Option+Shift+I")
    (hk "moveWindowToWorkspaceDown" "Option+Shift+U")
    (hk "moveColumnToWorkspaceUp" "Control+Option+I")
    (hk "moveColumnToWorkspaceDown" "Control+Option+U")
    (hk "moveColumnToWorkspace.0" "Control+Option+1")
    (hk "moveColumnToWorkspace.1" "Control+Option+2")
    (hk "moveColumnToWorkspace.2" "Control+Option+3")
    (hk "moveColumnToWorkspace.3" "Control+Option+4")
    (hk "moveColumnToWorkspace.4" "Control+Option+5")
    (hk "moveColumnToWorkspace.5" "Control+Option+6")
    (hk "moveColumnToWorkspace.6" "Control+Option+7")
    (hk "moveColumnToWorkspace.7" "Control+Option+8")
    (hk "moveColumnToWorkspace.8" "Control+Option+9")

    # ── 動かす（niri Mod+Ctrl） ──
    #    move.* は**向きに追従する統合移動**。主軸ならコンテナ間（consume/expel）、
    #    副軸ならコンテナ内を動く（判定は Direction.primaryStep(for: orientation)）。
    #    下の hjkl 段（moveColumn + moveWindowDown|Up）は niri の静的な対応表で、
    #    縦向きだと左右が死ぬ。両者は別家族なので衝突しない。差分14を参照。
    (hk "move.left" "Control+Option+Left Arrow")
    (hk "move.down" "Control+Option+Down Arrow")
    (hk "move.up" "Control+Option+Up Arrow")
    (hk "move.right" "Control+Option+Right Arrow")
    (hk "moveWindowDown" "Control+Option+J")
    (hk "moveWindowUp" "Control+Option+K")
    (hk "moveWindowDownOrToWorkspaceDown" "Unassigned")
    (hk "moveWindowUpOrToWorkspaceUp" "Unassigned")
    (hk "consumeWindowIntoColumn" "Option+Comma")
    (hk "expelWindowFromColumn" "Option+Period")

    # ── モニタ（niri Mod+Shift。方向 ID が無いので Next/Previous で代用） ──
    # 🔴 **Next が左・Previous が右**。名前と逆なので、hjkl に素直に当てると
    #    H で右・L で左に行って気持ち悪くなる（2026-10-27 の指摘）。
    #    実測（LG QHD x=-2560 / U32J59x x=0 の2画面構成）：
    #      LG(左) --prev--> U32J59x(右)、U32J59x(右) --next--> LG(左)
    #      どちらも端で**止まる**（循環しない。prev を2回押しても戻らない）
    #    理由＝ next/prev が走る順は **display の index 順**（display:1 =
    #    U32J59x = isMain、display:2 = LG）で、**x 座標の順ではない**。
    #    この構成では index 順が位置順の逆なので、next = 左 / prev = 右 になる。
    #    ⚠ **この入れ替えは今の構成に依存する。** モニタを差し替えたり管理対象を
    #      3枚にしたら index 順が変わって意味が反転しうる。確認は：
    #        omniwmctl query displays --json   # x 座標で左右を見る
    #        omniwmctl command focus-monitor prev / next  # どっちに動くか実測
    #    ※ OmniWM 0.7.6 に**方向指定のモニタフォーカスは無い**
    #      （`focus-monitor` は prev|next|last のみ。一方 `move-to-monitor` と
    #      `swap-workspace-with-monitor` は <left|right|up|down> を取る＝上流の穴）。
    #      なので「方向で指定する」には next/prev をこうして割り当てるしかない。
    #    ※ Sidecar（AirPlay）はワークスペースが未割当で、この循環に入らない。
    (hk "focusMonitorNext" "Option+Shift+H") # → 左へ
    (hk "focusMonitorPrevious" "Option+Shift+L") # → 右へ
    (hk "focusMonitorLast" "Option+Shift+Grave")
    # 🔴 矢印キーの正書法は "Left Arrow" 等（" Arrow" 必須）。"Left" だけの表記は
    #   不正バインドとして**ファイル全体が拒否**され、settings.toml.corrupt.N へ隔離
    #   →既定で書き直される（ipcEnabled=false に戻り omniwmctl ごと死ぬ）。
    #   2026-09-09 に実際に踏んだ（corrupt.1）。既定の settings.toml の表記が正。
    (hk "moveWorkspaceToMonitor.left" "Control+Option+Shift+Left Arrow")
    (hk "moveWorkspaceToMonitor.right" "Control+Option+Shift+Right Arrow")
    (hk "moveWorkspaceToMonitor.up" "Control+Option+Shift+Up Arrow")
    (hk "moveWorkspaceToMonitor.down" "Control+Option+Shift+Down Arrow")
    (hk "moveWindowToMonitor.left" "Control+Option+Shift+H")
    (hk "moveWindowToMonitor.right" "Control+Option+Shift+L")
    (hk "moveWindowToMonitor.up" "Control+Option+Shift+K")
    (hk "moveWindowToMonitor.down" "Control+Option+Shift+J")

    (hk "toggleFullscreen" "Option+Return")
    (hk "toggleNativeFullscreen" "Unassigned")
    (hk "moveColumn.left" "Control+Option+H")
    (hk "moveColumn.right" "Control+Option+L")
    # 縦向き専用。横向きでは primaryStep が nil を返すので何も起きない（差分15）。
    (hk "moveColumn.up" "Control+Option+Shift+I")
    (hk "moveColumn.down" "Control+Option+Shift+U")
    (hk "moveColumnToFirst" "Control+Option+Home")
    (hk "moveColumnToLast" "Control+Option+End")
    (hk "toggleColumnTabbed" "Option+T")
    (hk "focusColumnFirst" "Option+Home")
    (hk "focusColumnLast" "Option+End")

    # ── カラムの絶対指定：数字列を ws に明け渡した玉突きでここへ退避 ──
    #    段の意味（モニタへ送る）としては浮いている。要らなければ9件とも Unassigned に。
    #    普段は Option+H/L（Karabiner が Option+矢印 に変換・差分18）と
    #    Option+Home/End で回るので、使わないなら消してよい。
    (hk "focusColumn.0" "Control+Option+Shift+1")
    (hk "focusColumn.1" "Control+Option+Shift+2")
    (hk "focusColumn.2" "Control+Option+Shift+3")
    (hk "focusColumn.3" "Control+Option+Shift+4")
    (hk "focusColumn.4" "Control+Option+Shift+5")
    (hk "focusColumn.5" "Control+Option+Shift+6")
    (hk "focusColumn.6" "Control+Option+Shift+7")
    (hk "focusColumn.7" "Control+Option+Shift+8")
    (hk "focusColumn.8" "Control+Option+Shift+9")
    (hk "focusWindowInColumn.1" "Unassigned")
    (hk "focusWindowInColumn.2" "Unassigned")
    (hk "focusWindowInColumn.3" "Unassigned")
    (hk "focusWindowInColumn.4" "Unassigned")
    (hk "focusWindowInColumn.5" "Unassigned")
    (hk "focusWindowInColumn.6" "Unassigned")
    (hk "focusWindowInColumn.7" "Unassigned")
    (hk "focusWindowInColumn.8" "Unassigned")
    (hk "focusWindowInColumn.9" "Unassigned")
    # 置くなら Control+Option+Shift+U/I か、focusColumn を捨てて空く Ctrl+Opt+Shift+1..9。
    (hk "moveColumnToIndex.1" "Unassigned")
    (hk "moveColumnToIndex.2" "Unassigned")
    (hk "moveColumnToIndex.3" "Unassigned")
    (hk "moveColumnToIndex.4" "Unassigned")
    (hk "moveColumnToIndex.5" "Unassigned")
    (hk "moveColumnToIndex.6" "Unassigned")
    (hk "moveColumnToIndex.7" "Unassigned")
    (hk "moveColumnToIndex.8" "Unassigned")
    (hk "moveColumnToIndex.9" "Unassigned")

    (hk "cycleSizeForward" "Option+R")
    (hk "cycleSizeBackward" "Control+Option+R")
    (hk "cycleWindowPrimarySpanForward" "Unassigned")
    (hk "cycleWindowPrimarySpanBackward" "Unassigned")
    (hk "cycleWindowSecondarySpanForward" "Control+Option+Shift+R")
    (hk "cycleWindowSecondarySpanBackward" "Unassigned")
    (hk "toggleContainerFullPrimarySpan" "Option+Shift+F")
    (hk "expandContainerToAvailablePrimarySpan" "Control+Option+F")
    (hk "resetWindowSecondarySpan" "Unassigned")
    (hk "setContainerPrimarySpan.decrease10Percent" "Option+Minus")
    (hk "setContainerPrimarySpan.increase10Percent" "Option+Equal")
    (hk "setWindowPrimarySpan.decrease10Percent" "Unassigned")
    (hk "setWindowPrimarySpan.increase10Percent" "Unassigned")
    (hk "setWindowSecondarySpan.decrease10Percent" "Option+Shift+Minus")
    (hk "setWindowSecondarySpan.increase10Percent" "Option+Shift+Equal")
    (hk "balanceSizes" "Option+Shift+B")
    (hk "moveToRoot" "Unassigned")
    (hk "toggleSplit" "Unassigned")
    (hk "swapSplit" "Unassigned")
    (hk "resizeGrow.horizontal" "Unassigned")
    (hk "resizeGrow.vertical" "Unassigned")
    (hk "resizeShrink.horizontal" "Unassigned")
    (hk "resizeShrink.vertical" "Unassigned")
    (hk "resizeFocusedWindow.grow" "Unassigned")
    (hk "resizeFocusedWindow.shrink" "Unassigned")
    (hk "preselect.left" "Unassigned")
    (hk "preselect.right" "Unassigned")
    (hk "preselect.up" "Unassigned")
    (hk "preselect.down" "Unassigned")
    (hk "preselectClear" "Unassigned")
    (hk "openCommandPalette" "Control+Option+Space")
    (hk "raiseAllFloatingWindows" "Option+Shift+R")
    (hk "rescueOffscreenWindows" "Unassigned")
    (hk "toggleFocusedWindowFloating" "Option+V")
    (hk "toggleFloatingFocus" "Option+Shift+V")
    (hk "openMenuAnywhere" "Control+Option+M")
    (hk "toggleWorkspaceBarVisibility" "Unassigned")
    (hk "toggleHiddenBarPanel" "Unassigned")
    (hk "toggleQuakeTerminal" "Option+Grave")
    (hk "toggleWorkspaceLayout" "Unassigned")
    (hk "toggleOverview" "Option+O")
    (hk "toggleSystemStats" "Unassigned")

    # ──────────────────────────────────────────────────────────────────────
    # 0.7.4 で増えた 21件（2026-10-02 に追加）。全部 Unassigned のまま置く。
    #
    # 🔴 **ここを欠かすと settings.toml ごと既定へ飛ぶ。** 実測事故（2026-10-02）：
    #   0.6.4→0.7.4 に上げた直後の switch で、この配列が 169件のまま live へ書かれ、
    #   OmniWM が**不完全として全体を捨てて 190件の既定を書き戻した**。
    #   hotkeys 169件・ipcEnabled・followsWindowToMonitor・routing.arrangements
    #   （モニタ配置）が一撃で消えた。上流 #604「Updating 0.6.2 -> 0.6.3 wipes
    #   settings.toml (missing new required keys)」と同じ failure mode。
    #
    # ★ 一般形：**全件宣言は「全件」が版に依存する。** アプリ側の集合が増えたのに
    #   こちらが据え置くと、部分集合は「設定」ではなく「壊れたファイル」として扱われる。
    #   版を上げたら必ず `grep -c '^\[\[hotkeys\]\]' ~/.config/omniwm/settings.toml` と
    #   この配列の件数を突き合わせること（現在 190）。
    (hk "switchWorkspaceSlot.1" "Unassigned")
    (hk "switchWorkspaceSlot.2" "Unassigned")
    (hk "switchWorkspaceSlot.3" "Unassigned")
    (hk "switchWorkspaceSlot.4" "Unassigned")
    (hk "switchWorkspaceSlot.5" "Unassigned")
    (hk "switchWorkspaceSlot.6" "Unassigned")
    (hk "switchWorkspaceSlot.7" "Unassigned")
    (hk "switchWorkspaceSlot.8" "Unassigned")
    (hk "switchWorkspaceSlot.9" "Unassigned")
    (hk "moveToWorkspaceSlot.1" "Unassigned")
    (hk "moveToWorkspaceSlot.2" "Unassigned")
    (hk "moveToWorkspaceSlot.3" "Unassigned")
    (hk "moveToWorkspaceSlot.4" "Unassigned")
    (hk "moveToWorkspaceSlot.5" "Unassigned")
    (hk "moveToWorkspaceSlot.6" "Unassigned")
    (hk "moveToWorkspaceSlot.7" "Unassigned")
    (hk "moveToWorkspaceSlot.8" "Unassigned")
    (hk "moveToWorkspaceSlot.9" "Unassigned")
    # `closeFocusedWindow` は 0.6.4 では enum に在るのに hotkey ID に露出して
    # いなかった（冒頭「再現できないもの」の記述）。**0.7.4 で露出した**ので
    # niri 本家の `Mod+Q` と同じ Option+Q を当てた（差分11）。
    # Q/W/E/A/S/D/Z/X 段は 2026-09-08 の 3×3 撤回以降ずっと空いている。
    (hk "closeFocusedWindow" "Option+Q")
    # 0.7.4 の window marks（コマンドパレット／omniwmctl から付ける名前）。
    (hk "setWindowMark" "Unassigned")
    (hk "removeWindowMark" "Unassigned")
  ];

  # 既定は false。omniwmctl 用のソケットを開かせる（差分 1）。
  general.ipcEnabled = true;

  # 既定 true。アップデート通知を切る。更新は home.nix の version を上げて管理するので
  # アプリ側の更新チェックは要らない（live の settings.toml で `updateChecksEnabled` を実測）。
  general.updateChecksEnabled = false;

  # 既定 false。niri の move-column-to-workspace は既定で追従する（focus=true）ので、
  # niri 準拠のためには true が正しい。経緯と実測は冒頭の差分10を参照。
  focus.followsWindowToMonitor = true;

  # 既定は true。**既定と同じ値をわざわざ宣言している**のは、live の settings.toml が
  # false のまま取り残されているため（2026-10-02 発見）。
  #
  # ★ 経緯：87c9e70 が JankyBorders へ逃がすために `borders.enabled = false` を宣言し、
  #   24644e6（2026-09-05 のリセット）がその宣言を**消した**。だが merge-settings.nu は
  #   「テンプレが定義したキーだけ」を live に上書きする設計なので、**宣言を消しても
  #   live の値は戻らない**。結果 false が居座り、JankyBorders も退役済みなので
  #   2026-09-05 から**フォーカス枠が一切出ていなかった**。
  #
  # ★ 一般形：**宣言の削除は「既定に戻す」ではなく「管理をやめる」**。アプリが所有する
  #   設定ファイルでは、やめた瞬間の値がそのまま凍る。既定へ戻したいなら、既定値を
  #   明示的に宣言して1回流す必要がある。
  #
  #   枠が出たのを確認したら、この宣言は消してよい（live が true に書き変わるので
  #   同じ事故は起きない）。ただし別機体（tanegashima）に同じ false が残っている
  #   可能性があるので、両機で switch を回してから消すこと。
  borders.enabled = true;

  # 新しい列の既定幅をビューポートの 1/3 にする（既定 0.5・差分12）。
  # `containerPrimarySpanPresets` の1番目と同じ値なので Option+R のサイクルとも揃う。
  # 2026-10-04 に本人の指定で 2/3 → 1/3 に変更（3列が1画面に収まる）。
  #
  # ★ `niri.visibleContainerCount` は**この値が入っている限り効かない**。
  #   NiriLayoutEngine.resolvedContainerResetPrimarySpan が
  #   `defaultContainerPrimarySpan` を先に見て、nil のときだけ
  #   `1.0 / visibleContainerCount` へ落ちるフォールバックだから
  #   （＝「見える列数の上限」ではない。列は何本でも並ぶ）。
  #   GUI の Visible Containers スライダーを動かすと
  #   `defaultContainerPrimarySpan` を nil に落として 1/N へ委ねる作りなので、
  #   GUI で触ると**この宣言と毎回ぶつかる**。幅は宣言側で決めること。
  niri.defaultContainerPrimarySpan = 0.3333333333333333;

  # Overview をトラックパッドの上スワイプで開く（既定 false・差分13）。
  # 指の本数は既定の 4 本のまま。`gestures.fingerCount = 3`（Niri の列スクロール）と
  # 分けるため 3 にはしない。
  # ⚠ Overview の描画には**画面収録の権限**が要る（アクセシビリティ・入力監視と違い
  #   任意扱いなので未許可の可能性がある）。宣言できないので初回に GUI で許可する。
  gestures.overviewGestureEnabled = true;
}

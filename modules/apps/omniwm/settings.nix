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
#   169件を全件書いている（減らすと残りが Unassigned に飛ぶ）。逆に `workspaces` と
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
#        → `Option+Shift+H` = Previous / `Option+Shift+L` = Next で代用する。
#          2画面なら方向と一致する。3画面以上では単なる巡回に劣化する。
#          `Option+Shift+J/K` は嘘になるので**わざと空けてある**。
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
#        既定 false。false だと ~/Library/Caches/com.barut.OmniWM/ipc.sock が
#        開かず omniwmctl（query / watch / rule）が全滅する。
#
#   2. 方向キーを矢印から H/J/K/L へ（既定で矢印だった12件すべて）
#        focus.{left,down,up,right}      Option+矢印 → Option+H/J/K/L
#        moveColumn.{left,right}         → Control+Option+H/L   （niri `Mod+Ctrl+H/L`）
#        moveWindowDown / moveWindowUp   → Control+Option+J/K   （niri `Mod+Ctrl+J/K`）
#        moveWindowToMonitor.{左下上右}  → Control+Option+Shift+H/J/K/L
#      ※ 矢印キーは moveWorkspaceToMonitor.* だけが使う（差分9）。
#      ※ `move.{left,down,up,right}` は **Unassigned にした**。niri layout では
#        moveColumn（左右）と moveWindowDown/Up（上下）が同じ仕事をするため重複する。
#        dwindle layout へ切り替えるなら復活させること。
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
#      ⚠ Control+Option+Shift+U/I は**意図的に空けてある**。
#        moveColumnToIndex.1..9 を置きたくなったらそこか、上の Ctrl+Opt+Shift 数字列。
#
#   6. モニタ操作を Option+Shift 段へ（niri `Mod+Shift` = monitor に合わせる）
#        focusMonitorNext      Control+Option+Tab       → Option+Shift+L
#        focusMonitorPrevious  Control+Option+Shift+Tab → Option+Shift+H
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
    (hk "focus.left" "Option+H")
    (hk "focus.down" "Option+J")
    (hk "focus.up" "Option+K")
    (hk "focus.right" "Option+L")
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
    #    move.* は niri layout では moveColumn / moveWindowDown|Up と重複するので外す。
    (hk "move.left" "Unassigned")
    (hk "move.down" "Unassigned")
    (hk "move.up" "Unassigned")
    (hk "move.right" "Unassigned")
    (hk "moveWindowDown" "Control+Option+J")
    (hk "moveWindowUp" "Control+Option+K")
    (hk "moveWindowDownOrToWorkspaceDown" "Unassigned")
    (hk "moveWindowUpOrToWorkspaceUp" "Unassigned")
    (hk "consumeWindowIntoColumn" "Option+Comma")
    (hk "expelWindowFromColumn" "Option+Period")

    # ── モニタ（niri Mod+Shift。方向 ID が無いので Next/Previous で代用） ──
    (hk "focusMonitorNext" "Option+Shift+L")
    (hk "focusMonitorPrevious" "Option+Shift+H")
    (hk "focusMonitorLast" "Option+Shift+Grave")
    (hk "moveWorkspaceToMonitor.left" "Control+Option+Shift+Left")
    (hk "moveWorkspaceToMonitor.right" "Control+Option+Shift+Right")
    (hk "moveWorkspaceToMonitor.up" "Control+Option+Shift+Up")
    (hk "moveWorkspaceToMonitor.down" "Control+Option+Shift+Down")
    (hk "moveWindowToMonitor.left" "Control+Option+Shift+H")
    (hk "moveWindowToMonitor.right" "Control+Option+Shift+L")
    (hk "moveWindowToMonitor.up" "Control+Option+Shift+K")
    (hk "moveWindowToMonitor.down" "Control+Option+Shift+J")

    (hk "toggleFullscreen" "Option+Return")
    (hk "toggleNativeFullscreen" "Unassigned")
    (hk "moveColumn.left" "Control+Option+H")
    (hk "moveColumn.right" "Control+Option+L")
    (hk "moveColumn.up" "Unassigned")
    (hk "moveColumn.down" "Unassigned")
    (hk "moveColumnToFirst" "Control+Option+Home")
    (hk "moveColumnToLast" "Control+Option+End")
    (hk "toggleColumnTabbed" "Option+T")
    (hk "focusColumnFirst" "Option+Home")
    (hk "focusColumnLast" "Option+End")

    # ── カラムの絶対指定：数字列を ws に明け渡した玉突きでここへ退避 ──
    #    段の意味（モニタへ送る）としては浮いている。要らなければ9件とも Unassigned に。
    #    普段は Option+H/L と Option+Home/End で回るので、使わないなら消してよい。
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
    (hk "cycleWindowSecondarySpanForward" "Unassigned")
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
    (hk "openMenuAnywhere" "Control+Option+M")
    (hk "toggleWorkspaceBarVisibility" "Unassigned")
    (hk "toggleHiddenBarPanel" "Unassigned")
    (hk "toggleQuakeTerminal" "Option+Grave")
    (hk "toggleWorkspaceLayout" "Unassigned")
    (hk "toggleOverview" "Option+O")
    (hk "toggleSystemStats" "Unassigned")
  ];

  # 既定は false。omniwmctl 用のソケットを開かせる（差分 1）。
  general.ipcEnabled = true;
}

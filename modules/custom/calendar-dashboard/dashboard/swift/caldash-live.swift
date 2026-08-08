// caldash-live — カレンダー・ダッシュボード（本体 Google カレンダー×4面）
// 本体アプリを WKWebView で"最上位"ロード（iframe でないので X-Frame-Options 回避）。
// 全面が .default() データストア共有 → ログイン1回で全面認証・再起動で永続（実測済み）。
//
// レイアウト（4面）: 3 等幅カラム、左カラムは 2 月を縦スタック。
//   ┌────────┬────────┬────────┐
//   │ 今月    │ 今週    │ 来週    │   ← 来週で「次の月曜」も見える（週ビュー日曜起点問題の解）
//   ├────────┤        │        │
//   │ 来月    │        │        │
//   └────────┴────────┴────────┘
//
// モード: （無フラグ）interactive=通常窓・ログイン用 / --wallpaper=常在面（アイコン裏・透過・全Space・無人）
// 設定: ~/calendar-dashboard/caldash-config.json（env CALDASH_CONFIG で上書き）。
//       gap / zoom / weekZoom / baseZoom / baseWeekZoom / referenceWidth /
//       account(u/N) / tz / backgroundOpacity。
// 日次: ローカル 00:01 に再ロード（各面を今日基準に再アンカー＋来週/来月 URL 再計算）。
//       ※イベントデータ自体は本体 SPA が自前同期するので定期リロードはしない。
// 終了 = プロセス kill のみ。システム状態は何も変えない。
//
// セキュリティ（監査 2026-07-27 反映）:
//   - isInspectable / JS 自動 window.open は無人常駐(--wallpaper)では無効（認証 view への侵入面を絞る）。
//   - createWebViewWith / decidePolicy は wallpaper 時 Google 一族ホストのみ許可（認証 view の外部誘導阻止）。
//   - .default() に本人の常時 Google セッション cookie が永続する点は自覚の上で受容（ブラウザ同等リスク）。

import Cocoa
import WebKit

let SAFARI_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
let WALLPAPER = CommandLine.arguments.contains("--wallpaper")

// wallpaper mode 専用: Google カレンダー本体のクロム（トップバー・サイドバー）を消して
// 盤面だけ残す。class 名は毎リリースでハッシュ化される（例: .aRlgFf）ため landmark で当てる。
// トップバー(=role='banner')は display:none で真に消す。左サイドバー（Create/ミニカレ/
// カレンダー一覧/フッター）は Google が非-landmark で組んでいる可能性が高いため、
// role='main' を viewport 全面に position:fixed で被せる「構造非依存」戦略で覆い隠す。
// これで DOM を残したまま視覚的にサイドバーが消え、Google の class ハッシュ変更にも
// 巻き込まれない。interactive mode ではログイン・ナビ用に UI を温存する。
// クロム消し専用。透過は NSWindow.alphaValue で window 全体に一律適用するので、
// ここで CSS 側の背景を触る必要は無い（触ると event card や時刻軸が二重に透過して
// 変な見え方になる）。html/body の overflow だけ抑えてスクロール暴発を防ぐ。
// today ハイライト: GCal は today 要素に `.F262Ye` class を付けるので、週/月ビューの
// columnheader（曜日ヘッダ）と gridcell（events grid の today 列）に薄い青背景。
// 内側の要素にも .F262Ye は伝播するが role で絞ることで stacking の重色を防ぐ。
let HIDE_CHROME_CSS = """
[role='banner'] { display: none !important; }
[role='main'] {
  position: fixed !important;
  inset: 0 !important;
  width: 100vw !important;
  height: 100vh !important;
  z-index: 999999 !important;
}
html, body { overflow: hidden !important; margin: 0 !important; padding: 0 !important; }
[role='columnheader'].F262Ye,
[role='gridcell'].F262Ye {
  background-color: rgba(66, 133, 244, 0.15) !important;
}
"""

// 週ペイン限定: イベントブロックの文字だけ縮小して1イベントあたりの情報量を上げる
// （pane zoom と違いグリッドの高さは変えないので、週ペインの下に黒帯が出ない）。
// data-eventid はイベント要素の安定属性。実効サイズは週ペインの pageZoom が掛かるので、
// config の weekZoom（式モードなら baseWeekZoom）に応じて見え方が変わる。
// 月ペインには当てない: 月ビューのチップは GCal の JS がフォント計測込みで絶対配置する
// ため、CSS でフォントだけ縮めると複数日バーと通常チップの文字が重なる（2026-08-07
// スクショ実測）。週ビューは時間ベース配置なので安全。
let WEEK_EVENT_FONT_CSS = """
[data-eventid], [data-eventid] span {
  font-size: 10px !important;
  line-height: 1.2 !important;
}
"""

// ---- 設定（既定値。config で上書き）----
var ACCOUNT = 0
var TZ_ID   = "America/Chicago"
var GAP: CGFloat = 6
var MONTH_ZOOM: CGFloat = 0.75       // 月ペイン pageZoom（<1 で文字を小さく＝密度↑）
var WEEK_ZOOM: CGFloat = 0.5         // 週ペイン pageZoom（1日 0-24 時をスクロール無しで収める用）
// GCal 週ビューの hour gutter CSS 幅（.lqYlwe が JS で固定する 96px、実測）。
// 中央 pane (今週) はこれを内部で消費するので、幅を +GCAL_WEEK_GUTTER_PX*weekZoom
// 余分にとって右 pane (来週=gutter 消去済) の 1 日列幅と揃える。
let GCAL_WEEK_GUTTER_PX: CGFloat = 96
// 解像度スケール式（referenceWidth が config にあると式モード起動＝main モニタ幅で自動追随）。
// 例: baseMonthZoom=0.9 referenceWidth=2560 → 2560幅で 0.9・3840幅で ~0.735・5120幅で ~0.636（sqrt ダンパー）。
// 現画面幅の変化（モニタ挿抜・SetResolution）は didChangeScreenParametersNotification で購読して再計算。
var BASE_MONTH_ZOOM: CGFloat? = nil
var BASE_WEEK_ZOOM: CGFloat? = nil
var REFERENCE_WIDTH: CGFloat? = nil
// 背景 alpha（config: backgroundOpacity）。1.0=完全不透明、<1.0 で壁紙が透ける。
// window.isOpaque + backgroundColor + GridView.layer + WKWebView.drawsBackground +
// CSS 注入の全レイヤーに一貫適用する（どこか一箇所でも opaque だと透過は死ぬ）。
var BG_OPACITY: CGFloat = 1.0

struct Config: Codable {
    var gap: Double?; var monthZoom: Double?; var weekZoom: Double?
    var baseMonthZoom: Double?; var baseWeekZoom: Double?; var referenceWidth: Double?
    var account: Int?; var tz: String?
    var backgroundOpacity: Double?
}
// 設定ファイル: 既定 ~/.config/caldash/config.json (XDG_CONFIG_HOME 準拠、
// 環境変数 XDG_CONFIG_HOME が空でなければそちらを尊重)。CALDASH_CONFIG 環境変数で
// 個別 override 可能。旧 ~/calendar-dashboard/caldash-config.json は home-manager
// activation が起動前に新パスへ mv 済み。
func defaultConfigPath() -> String {
    let env = ProcessInfo.processInfo.environment
    let xdg = (env["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 })
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config").path
    return "\(xdg)/caldash/config.json"
}
func loadConfig() {
    let path = ProcessInfo.processInfo.environment["CALDASH_CONFIG"] ?? defaultConfigPath()
    print("[caldash] config file: \(path)")
    guard let data = FileManager.default.contents(atPath: path),
          let c = try? JSONDecoder().decode(Config.self, from: data) else { return }
    if let v = c.gap { GAP = CGFloat(v) }
    if let v = c.monthZoom { MONTH_ZOOM = CGFloat(v) }
    if let v = c.weekZoom { WEEK_ZOOM = CGFloat(v) }
    if let v = c.baseMonthZoom { BASE_MONTH_ZOOM = CGFloat(v) }
    if let v = c.baseWeekZoom { BASE_WEEK_ZOOM = CGFloat(v) }
    if let v = c.referenceWidth { REFERENCE_WIDTH = CGFloat(v) }
    if let v = c.account { ACCOUNT = v }
    if let v = c.tz { TZ_ID = v }
    if let v = c.backgroundOpacity { BG_OPACITY = max(0, min(1, CGFloat(v))) }
    print("[caldash] config: gap=\(GAP) monthZoom=\(MONTH_ZOOM) weekZoom=\(WEEK_ZOOM) u/\(ACCOUNT) \(TZ_ID) opacity=\(BG_OPACITY)")
    if let ref = REFERENCE_WIDTH {
        print("[caldash] formula: baseMonthZoom=\(BASE_MONTH_ZOOM ?? MONTH_ZOOM) baseWeekZoom=\(BASE_WEEK_ZOOM ?? WEEK_ZOOM) referenceWidth=\(ref)")
    }
}

// 解像度スケール式（sqrt ダンパー）。base * sqrt(ref/current)。
// 現画面が ref より狭い→zoom↑（文字↑）、広い→zoom↓（密度↑）。sqrt で振れ幅を抑える。
func effectiveZoom(base: CGFloat, ref: CGFloat, current: CGFloat) -> CGFloat {
    return base * (ref / max(1, current)).squareRoot()
}

func cal() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: TZ_ID) ?? .current
    return c
}
func nextMonthYM() -> (Int, Int) {
    let c = cal().dateComponents([.year, .month], from: Date())
    var y = c.year!, m = c.month! + 1
    if m > 12 { m = 1; y += 1 }
    return (y, m)
}
func nextWeekYMD() -> (Int, Int, Int) {
    let d = cal().date(byAdding: .day, value: 7, to: Date())!
    let c = cal().dateComponents([.year, .month, .day], from: d)
    return (c.year!, c.month!, c.day!)
}
func thisMonthYM() -> (Int, Int) {
    let c = cal().dateComponents([.year, .month], from: Date())
    return (c.year!, c.month!)
}
// 4 pane（GridView.layout の panes[0..3] と順序を揃える）:
//   [0] 今月 (左上) / [1] 来月 (左下) / [2] 今週 (中央) / [3] 来週 (右)
// 今月も明示日付 URL にする（素の /month と同じ表示。境界週デデュープ JS が
// URL から対象月を読むため必須。日次 reanchor で当日基準に再計算される）。
func paneURLs() -> [String] {
    let base = "https://calendar.google.com/calendar/u/\(ACCOUNT)/r"
    let (ty, tm) = thisMonthYM()
    let (ny, nm) = nextMonthYM()
    let (wy, wm, wd) = nextWeekYMD()
    return [
        "\(base)/month/\(ty)/\(tm)/1",     // 今月
        "\(base)/month/\(ny)/\(nm)/1",     // 来月
        "\(base)/week",                    // 今週
        "\(base)/week/\(wy)/\(wm)/\(wd)"   // 来週
    ]
}

// 月ペインの pane 固有 JS（wallpaper 専用）。2つの仕事をする：
//
// ①境界週デデュープ。GCal 月ビューは常に完全週で描画するため、月境界が週の途中だと
//   境界週（例: 8/31–9/6）が今月ペイン最下段と来月ペイン最上段の両方に出る。
//   **週行数が多い方のペイン**から境界週を隠し、両ペインの行数（＝1週の縦幅）を
//   揃える（同数のときは来月側を隠す＝今月を完全に保つ）。月初が週初めの月は
//   重複自体が無いので何もしない。
// ②today 強調。GCal の today marker class（.F262Ye）は週ビューの gridcell にしか
//   付かない（月ビューの today セルには付かない。2026-08-07 スクショ実測）ため、
//   CSS では当てられず、日付演算で today セルを特定して塗る。月ビューの gridcell は
//   イベント欄のみで日付数字の帯をカバーしない（同日実測）ので、行に背面オーバーレイ
//   （行の全高 × セルの列幅）を敷いて週ビューの today 列と同色 rgba(66,133,244,.15) で
//   塗る＝週/月でトーンが揃う。デデュープで today の週が今月ペインから隠れている日は、
//   来月ペイン側の境界週（行0）で同じ強調が光る。
//
// 週開始曜日・行数は DOM と Date から自己推論するので config（週開始設定）に
// 非依存・毎月自動適応。Swift から渡すのはペインの役割（current/next）だけ。
// class ハッシュに依存せず role（row/gridcell）だけで当てる。日番号は h2 の
// 「N日」表記（日本語 locale の月初セル「9月1日」）を優先し、無ければ末尾の数値。
func monthPaneJS(role: String) -> String {
    return #"""
    (() => {
      const ROLE = '\#(role)';   // 'current' | 'next'

      //---- DOM 読み取り -------------------------------------------------

      // セルの日番号。「N日」（日本語 locale の月初セル）優先、無ければ末尾の数値
      const dayNum = c => {
        if (!c) return NaN;
        const t = (c.querySelector('h2') || c).textContent || '';
        const jp = t.match(/(\d+)日/);
        if (jp) return +jp[1];
        const all = t.match(/\d+/g);
        return all ? +all[all.length - 1] : NaN;
      };

      // URL からペインの対象月を読む（/month/YYYY/M/D。paneURLs が明示日付で組む前提）
      const paneMonth = () => {
        const m = location.pathname.match(/\/month\/(\d+)\/(\d+)/);
        return m ? { y: +m[1], mon: +m[2] } : null;
      };

      // 月グリッドの週行を収集。親要素ごとにグループ化し最大グループを本体とみなす
      // （ビュー遷移アニメで旧ビューの grid が DOM に残る場合への防御）。
      const weekRows = () => {
        const cells = [...document.querySelectorAll("[role='main'] [role='gridcell']")];
        const groups = new Map();
        for (const c of cells) {
          const r = c.closest("[role='row']");
          if (!r || !r.parentElement) continue;
          if (!groups.has(r.parentElement)) groups.set(r.parentElement, new Set());
          groups.get(r.parentElement).add(r);
        }
        let rows = [];
        for (const g of groups.values()) {
          const arr = [...g].filter(r => r.getBoundingClientRect().width > 0 || r.style.display === 'none');
          if (arr.length > rows.length) rows = arr;
        }
        return rows.length >= 4 ? rows : null;
      };

      //---- 暦の演算 -----------------------------------------------------
      // 全材料を ctx にまとめる。組み立てられなければ null（→その回は no-op）。
      // ctx = { rows, cy, cm, ny, nm, dup, offsetOf, rowsOf }
      //   cy/cm = ペアの「今月」・ny/nm = ペアの「来月」（自ペインの role から復元）
      const buildContext = () => {
        const pane = paneMonth();
        const rows = pane && weekRows();
        if (!rows) return null;
        // 2行目の先頭セルは必ず当月内（day 2..8）→ そこから列0の曜日を逆算
        const k = dayNum(rows[1].querySelector("[role='gridcell']"));
        if (!k || isNaN(k)) return null;
        const col0Dow = new Date(pane.y, pane.mon - 1, k).getDay();
        const daysIn = (yy, mm) => new Date(yy, mm, 0).getDate();
        const offsetOf = (yy, mm) => ((new Date(yy, mm - 1, 1).getDay() - col0Dow) + 7) % 7;
        const rowsOf = (yy, mm) => Math.ceil((offsetOf(yy, mm) + daysIn(yy, mm)) / 7);
        let cy = pane.y, cm = pane.mon;
        if (ROLE === 'next') { cm--; if (cm < 1) { cm = 12; cy--; } }
        let ny = cy, nm = cm + 1; if (nm > 12) { nm = 1; ny++; }
        const dup = offsetOf(ny, nm) !== 0;   // 月初＝週初なら境界週の重複なし
        return { rows, cy, cm, ny, nm, dup, offsetOf, rowsOf };
      };

      //---- ① 境界週デデュープ（多い方が隠す・同数は来月側）--------------
      const dedupeBoundaryWeek = ({ rows, cy, cm, ny, nm, dup, rowsOf }) => {
        if (!dup) return;
        const curHides = rowsOf(cy, cm) > rowsOf(ny, nm);
        if (curHides !== (ROLE === 'current')) return;
        const target = ROLE === 'current' ? rows[rows.length - 1] : rows[0];
        // 隠す前の実測サニティチェック: 境界週は当月外の日番号を含むはず
        const nums = [...target.querySelectorAll("[role='gridcell']")].map(dayNum);
        const looksBoundary = ROLE === 'current' ? nums.some(n => n <= 7) : nums.some(n => n >= 8);
        if (looksBoundary && target.style.display !== 'none') target.style.display = 'none';
      };

      //---- ② today 強調（行全高×列幅の背面オーバーレイ）------------------
      const highlightToday = ({ rows, cy, cm, dup, offsetOf, rowsOf }) => {
        const now = new Date();
        if (now.getFullYear() !== cy || now.getMonth() + 1 !== cm) return;  // today は常にペアの「今月」側
        const pos = offsetOf(cy, cm) + now.getDate() - 1;
        const tRow = Math.floor(pos / 7), tCol = pos % 7;
        let cellRow = null;
        if (ROLE === 'current') {
          cellRow = rows[tRow];                        // 境界行が隠れていれば下の可視チェックで弾く
        } else if (dup && tRow === rowsOf(cy, cm) - 1) {
          cellRow = rows[0];                           // 来月ペインの行0＝境界週に today がいる
        }
        if (!cellRow || cellRow.style.display === 'none') return;
        const cell = cellRow.querySelectorAll("[role='gridcell']")[tCol];
        if (!cell || dayNum(cell) !== now.getDate()) return;   // 位置演算と実測がズレたら塗らない
        // gridcell はイベント欄のみ（日付数字の帯を含まない）ので、行の全高に
        // 背面オーバーレイを敷く。行の先頭子として挿入し、GCal 側のセル・チップが
        // どれも positioned（同じ stacking 層で DOM 順に描画される）なのを利用して
        // 背面に置く＝週ビューの today 列と同じ見え方。position 依存を避けようと
        // z-index:-1 を付けると、行自身の背景の裏に回って**塗りが見えなくなる**
        // （2026-08-07 実測）。見え方が壊れたらここを疑う。
        let ov = cellRow.querySelector(':scope > .caldash-today-ov');
        if (!ov) {
          ov = document.createElement('div');
          ov.className = 'caldash-today-ov';
          ov.style.position = 'absolute';
          ov.style.top = '0';
          ov.style.height = '100%';
          ov.style.pointerEvents = 'none';
          ov.style.backgroundColor = 'rgba(66, 133, 244, 0.15)';
          if (getComputedStyle(cellRow).position === 'static') cellRow.style.position = 'relative';
          cellRow.insertBefore(ov, cellRow.firstChild);
        }
        const rr = cellRow.getBoundingClientRect(), cr = cell.getBoundingClientRect();
        ov.style.left = (cr.left - rr.left) + 'px';
        ov.style.width = cr.width + 'px';
      };

      //---- 実行ループ ---------------------------------------------------
      const apply = () => {
        const ctx = buildContext();
        if (!ctx) return;
        dedupeBoundaryWeek(ctx);
        highlightToday(ctx);
      };
      apply();
      setInterval(apply, 3000);   // SPA の DOM 再構築に追随（冪等・再適用）
    })();
    """#
}

// Google 一族のホストか（M1: 無人常駐で認証 view を外部 URL に飛ばさせない allowlist）
func isGoogleHost(_ host: String?) -> Bool {
    guard let h = host else { return true }
    let owned = ["google.com", "gstatic.com", "googleapis.com", "googleusercontent.com", "youtube.com"]
    return owned.contains { h == $0 || h.hasSuffix("." + $0) }
}

// 3 カラム、左は月を縦スタック。middleExtraWidth が >0 なら中央 pane がその分広く、
// 左右 pane は残りを等分する（左 lw + 中央 lw+extra + 右 lw + gap*2 = W）。
// extra は AppDelegate が「中央 pane の hour gutter を左右 pane と day col 幅で
// 揃えるためのオフセット」として設定する。isFlipped=true で左上原点。
final class GridView: NSView {
    var panes: [NSView] = []
    var middleExtraWidth: CGFloat = 0
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        guard panes.count == 4 else { return }
        let W = bounds.width, H = bounds.height
        let usable = max(0, W - 2 * GAP)
        let lw = max(0, (usable - middleExtraWidth) / 3)
        let mw = lw + middleExtraWidth
        let rw = lw
        let monthH = max(0, (H - GAP) / 2)
        panes[0].frame = NSRect(x: 0,                       y: 0,             width: lw, height: monthH) // 今月（左上）
        panes[1].frame = NSRect(x: 0,                       y: monthH + GAP,  width: lw, height: monthH) // 来月（左下）
        panes[2].frame = NSRect(x: lw + GAP,                y: 0,             width: mw, height: H)      // 今週（中央、+extra）
        panes[3].frame = NSRect(x: lw + GAP + mw + GAP,     y: 0,             width: rw, height: H)      // 来週（右）
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate, WKNavigationDelegate {
    // wallpaper mode: 各 NSScreen に 1 window ずつ描画（cp-dash と同型）。
    // interactive mode: windows.count == 1（中央窓 1 本のみ）。
    // 3 配列は screen index で揃える（webs[i] は screen i の 5 pane）。
    var windows: [NSWindow] = []
    var grids: [GridView] = []
    var webs: [[WKWebView]] = []
    let store = WKWebsiteDataStore.default()   // ログイン共有＆永続（実測済み）

    // desktop-switch からの信号ハンドラ（wallpaper mode 限定）。retain 必須。
    // 生の signal(2) は async-signal-safe な API しか呼べず NSWindow 不可なので
    // DispatchSource で main queue に配信して安全にウィンドウ操作する。
    var switchSource: DispatchSourceSignal?

    // 式モードか（REFERENCE_WIDTH 指定時のみ）
    var formulaMode: Bool { REFERENCE_WIDTH != nil }

    // 指定 screen 幅から effective zoom を算出。式 off なら config の静的値を返す。
    func computeEffectiveZooms(for screen: NSScreen) -> (CGFloat, CGFloat) {
        guard let ref = REFERENCE_WIDTH else { return (MONTH_ZOOM, WEEK_ZOOM) }
        let baseM = BASE_MONTH_ZOOM ?? MONTH_ZOOM
        let baseW = BASE_WEEK_ZOOM ?? WEEK_ZOOM
        let w = screen.frame.width
        return (effectiveZoom(base: baseM, ref: ref, current: w),
                effectiveZoom(base: baseW, ref: ref, current: w))
    }

    func makeWeb(_ urlStr: String, zoom: CGFloat, extraCSS: String = "", extraJS: String = "") -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = store
        // M2: 無人常駐では JS の自動 window.open を禁止。ログインは gesture 起点なので interactive では許可。
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = !WALLPAPER
        // wallpaper mode 限定: 盤面だけ残す CSS を毎ロード注入（documentElement 直下なので
        // SPA の DOM 再構築で剥がれない）。extraCSS で pane 固有ルール（例: 来週の時間軸
        // オフ）を後付けできる。interactive では UI 温存でログイン導線を確保。
        if WALLPAPER {
            let css = HIDE_CHROME_CSS + "\n" + extraCSS
            // MutationObserver で document.head を監視、style 要素が消えたら即再注入。
            // 日次 reanchor での URL 再読込では atDocumentEnd で毎回再発火するので、
            // ここで確保するのは「同一ページ内で Google が SPA 的に head を弄っても
            // CSS を失わない」保険。observer が万一漏らしても setInterval で数秒後に復旧。
            let js = """
            (() => {
              const CSS = `\(css)`;
              const inject = () => {
                if (document.getElementById('caldash-hide-chrome')) return;
                const s = document.createElement('style');
                s.id = 'caldash-hide-chrome';
                s.textContent = CSS;
                (document.head || document.documentElement).appendChild(s);
              };
              inject();
              // head の childList 変化を監視。head 自体が置換されたら subtree で拾えないので
              // documentElement を root にして childList を見る（head/body 置換にも耐える）。
              new MutationObserver(inject).observe(document.documentElement, { childList: true, subtree: false });
              new MutationObserver(inject).observe(document.head || document.documentElement, { childList: true });
              // 保険: 3 秒毎に生存チェック（observer が漏らしても最大 3 秒で復旧）。
              setInterval(inject, 3000);
            })();
            """
            let script = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            cfg.userContentController.addUserScript(script)
            // pane 固有の JS（例: 月ペインの境界週デデュープ）。CSS と同じく wallpaper 限定。
            if !extraJS.isEmpty {
                cfg.userContentController.addUserScript(
                    WKUserScript(source: extraJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            }
        }
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.customUserAgent = SAFARI_UA
        wv.uiDelegate = self
        wv.navigationDelegate = self
        wv.pageZoom = zoom
        // H2: 認証済み Google セッションに Inspector を残さない（無人常駐では無効）。
        if #available(macOS 13.3, *) { wv.isInspectable = !WALLPAPER }
        wv.load(URLRequest(url: URL(string: urlStr)!))
        return wv
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        if WALLPAPER {
            setupWallpaperWindows()
            // 解像度/モニタ挿抜/main 切替を購読。screen 数の変化なら全再構築、
            // 数同じ（解像度変更のみ）なら zoom + frame を追随。
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                self?.reapplyForCurrentScreens()
            }
            // desktop-switch IPC: SIGUSR1 で ~/.local/state/desktop-switch/cmd を読み、
            // 該当 screen だけ show/hide する（引数を渡せない signal の穴埋め）。
            // 生 signal(2) は default で終了なので事前に SIG_IGN で無効化してから
            // DispatchSource で main queue に配信して NSWindow を安全に操作。
            signal(SIGUSR1, SIG_IGN)
            switchSource = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
            switchSource?.setEventHandler { [weak self] in self?.handleSwitchCommand() }
            switchSource?.resume()
            // launchctl kickstart 経由の再起動でも表示状態を保つため、起動時に state を
            // 読んで各 window の visibility を復元。state 無い（初回）なら全 screen 見せる。
            applyPersistedState()
        } else {
            // Interactive: 中央 1 窓に 5 pane grid。login/デバッグ用。
            let initialScreen = NSScreen.main ?? NSScreen.screens[0]
            let (z, wz) = computeEffectiveZooms(for: initialScreen)
            let (grid, paneWebs) = makeGrid(screenFrame: NSRect(x: 0, y: 0, width: 1800, height: 1050),
                                            zoom: z, weekZoom: wz)
            let w = NSWindow(contentRect: grid.frame,
                             styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "caldash — 今日/今週/来週/今月/来月（--wallpaper で常在面化）"
            w.contentView = grid
            w.center()
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            windows = [w]
            grids = [grid]
            webs = [paneWebs]
        }
        scheduleDailyReanchor()
    }

    // GridView + 5 WKWebView を組み立てて (grid, webs) を返す。呼び出し側で
    // self.grids/self.webs に append（screen index を揃えるため）。
    private func makeGrid(screenFrame: NSRect, zoom: CGFloat, weekZoom: CGFloat) -> (GridView, [WKWebView]) {
        let grid = GridView(frame: screenFrame)
        grid.wantsLayer = true
        // pane 間 GAP を黒で埋める（透過は window.alphaValue で全体一律にかけるので
        // ここは触らない）。
        grid.layer?.backgroundColor = NSColor.black.cgColor
        grid.autoresizingMask = [.width, .height]
        // 中央 pane (今週) の hour gutter 分を余分に幅取って左右と day col 幅を揃える。
        // pageZoom が掛かるので device px = CSS px * weekZoom。
        grid.middleExtraWidth = GCAL_WEEK_GUTTER_PX * weekZoom
        let zooms: [CGFloat] = [zoom, zoom, weekZoom, weekZoom]  // 今月/来月/今週/来週
        // 来週 (index 3) は時間ラベル gutter を完全に消去し、day headers も events grid
        // 本体も左端に寄せる。GCal 週ビュー DOM (2026-07-30 時点):
        //   .UqLcs  = 上部 Texas/Japan チップコンテナ（.sS0sZd + .kL3bhb 内包）
        //   .FDbe8b = day headers / all-day 行の左端 spacer（時間 gutter 幅を予約）
        //   .EDDeke = events grid 行の左端 spacer
        //   .lqYlwe = hour 列コンテナ（.R6TFwe 内包）。JS が 96px 固定 width を設定するので
        //             R6TFwe だけ hide しても 96px 残る → 親ごと display:none で潰す。
        //             .lqYlwe と .mDPmMe（events grid）は .uEzZIb の flex sibling なので
        //             .lqYlwe を消せば .mDPmMe が全幅（96px 分左へ）に広がる。
        // NOTE: Google の class 名はハッシュで release 毎に変わる可能性あり（fragile）。
        //       壊れたら wallpaper mode で isInspectable=true にして再インスペクト。
        // 来月ペインは曜日ヘッダー行（MON TUE …）を隠す。縦スタックで今月ペインの
        // ヘッダーと重複するため。:has() で columnheader を含む行だけ落とす
        // （macOS 13+/Safari 15.4+ の WebKit で利用可。today 強調は CSS では当てられず
        // JS 側 = monthPaneJS ②参照）。
        let nextMonthCSS = "[role='row']:has([role='columnheader']) { display: none !important; }"
        let extraCSSs: [String] = ["", nextMonthCSS, WEEK_EVENT_FONT_CSS,
            WEEK_EVENT_FONT_CSS + "\n.lqYlwe, .UqLcs, .FDbe8b, .EDDeke { display: none !important; }"]
        // 月ペイン2枚に境界週デデュープ＋today 強調 JS（monthPaneJS 冒頭コメント参照）。
        let extraJSs: [String] = [monthPaneJS(role: "current"), monthPaneJS(role: "next"), "", ""]
        let urls = paneURLs()
        let paneWebs = urls.indices.map { i in
            makeWeb(urls[i], zoom: zooms[i], extraCSS: extraCSSs[i], extraJS: extraJSs[i])
        }
        grid.panes = paneWebs
        paneWebs.forEach { grid.addSubview($0) }
        return (grid, paneWebs)
    }

    // wallpaper mode: NSScreen.screens をループして各 screen に 1 window ずつ生成。
    // 呼び出し前に windows/grids/webs をクリアしておくこと（reapplyForCurrentScreens
    // の全再構築パスで再利用される）。
    private func setupWallpaperWindows() {
        for (i, screen) in NSScreen.screens.enumerated() {
            // visibleFrame は menu bar と dock を除外した領域。壁紙 level の window でも
            // menu bar の下に潜り込むと透過越しに calendar が menu bar に混じって
            // メニュー文字が読みにくくなる（透過運用で顕在化）。ここで避ける。
            let area = screen.visibleFrame
            let (zoom, weekZoom) = computeEffectiveZooms(for: screen)
            let (grid, paneWebs) = makeGrid(screenFrame: NSRect(origin: .zero, size: area.size),
                                            zoom: zoom, weekZoom: weekZoom)
            let w = NSWindow(contentRect: area, styleMask: .borderless,
                             backing: .buffered, defer: false)
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            w.ignoresMouseEvents = true
            w.backgroundColor = .black
            // NSWindow.alphaValue で window 全体を一律に半透明化（compositor level）。
            // これで event card / 時刻軸 / grid line / 文字も含めて uniform に壁紙が透ける。
            // isOpaque は alpha<1 の時 false にしないと合成が壊れる。opacity=1.0 なら
            // isOpaque=true で描画パス最適化（AppKit が全画面 opaque 扱いで速い）。
            w.isOpaque = (BG_OPACITY >= 1.0)
            w.alphaValue = BG_OPACITY
            w.contentView = grid
            w.setFrame(area, display: true)
            w.orderFrontRegardless()
            windows.append(w)
            grids.append(grid)
            webs.append(paneWebs)
            print("[caldash] wallpaper screen[\(i)] visible=\(area.size) zoom=\(zoom)/\(weekZoom)")
        }
    }

    // 日次アンカー更新：ローカル 00:01 に全面を再ロード。DST でずれないよう Calendar で厳密算出。
    func scheduleDailyReanchor() {
        guard let next = cal().nextDate(after: Date(),
                                        matching: DateComponents(hour: 0, minute: 1, second: 0),
                                        matchingPolicy: .nextTime) else { return }
        let t = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            self?.reanchor()
            self?.scheduleDailyReanchor()
        }
        RunLoop.main.add(t, forMode: .common)
        print("[caldash] next re-anchor at \(next)")
    }
    func reanchor() {
        let urls = paneURLs()   // 来週/来月 URL は当日基準で再計算される
        for screenWebs in webs {
            for (i, wv) in screenWebs.enumerated() where i < urls.count {
                if let u = URL(string: urls[i]) { wv.load(URLRequest(url: u)) }
            }
        }
        print("[caldash] re-anchored across \(webs.count) screen(s)")
    }

    // 画面変化（モニタ挿抜・main 切替・解像度変更）に追随。screen 数が変わったら
    // 全 window を tear down して setupWallpaperWindows() で作り直し、同じなら
    // 各 window の frame と zoom を更新するだけ。interactive mode では no-op。
    func reapplyForCurrentScreens() {
        guard WALLPAPER else { return }
        let screens = NSScreen.screens
        if screens.count != windows.count {
            print("[caldash] screen count \(windows.count) → \(screens.count), rebuilding")
            for w in windows { w.orderOut(nil); w.close() }
            windows.removeAll(); grids.removeAll(); webs.removeAll()
            setupWallpaperWindows()
            return
        }
        for (i, w) in windows.enumerated() {
            guard let screen = w.screen ?? (i < screens.count ? screens[i] : nil) else { continue }
            let area = screen.visibleFrame
            if w.frame != area { w.setFrame(area, display: true) }
            guard formulaMode, i < webs.count else { continue }
            let (nz, nwz) = computeEffectiveZooms(for: screen)
            let zooms: [CGFloat] = [nz, nz, nwz, nwz]  // 今月/来月/今週/来週
            for (j, wv) in webs[i].enumerated() where j < zooms.count {
                if wv.pageZoom != zooms[j] { wv.pageZoom = zooms[j] }
            }
        }
    }

    // 与えた monitor-name に一致する NSScreen を持つ window の index を返す。
    // aerospace の monitor-name（例 "Mi TV" / "Built-in Display"）と NSScreen.localizedName
    // が同一なので照合可能。同名複数モニタは順に返す。
    private func windowIndices(matching name: String) -> [Int] {
        return windows.enumerated().compactMap { (i, w) in
            (w.screen?.localizedName == name) ? i : nil
        }
    }

    // 起動時に ~/.local/state/desktop-switch/state を読んで per-screen 表示状態を復元。
    // 書式: 各行 "<monitor-name>=<layer>"（layer=caldash/cp/wallpaper）。未記載の screen
    // は show で残す（初回起動 or 部分状態の互換）。reload（kickstart）後の状態保持のため必須。
    private func applyPersistedState() {
        let path = ("\(NSHomeDirectory())/.local/state/desktop-switch/state" as NSString).expandingTildeInPath
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        for line in raw.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = String(parts[0]), layer = String(parts[1])
            for idx in windowIndices(matching: name) {
                if layer == "caldash" { windows[idx].orderFrontRegardless() }
                else                  { windows[idx].orderOut(nil) }
            }
        }
        print("[caldash] state restored from \(path)")
    }

    // desktop-switch IPC: SIGUSR1 で ~/.local/state/desktop-switch/cmd を読んで dispatch。
    // 書式は1行、"layer=<name>;screen=<monitor-name|all>"。layer が "caldash" なら該当
    // window を show、それ以外（cp/wallpaper）なら hide。screen=all は全 window に一括適用。
    // command file 不在 or parse 失敗は黙って noop（信号バタつきで壊さない）。
    private func handleSwitchCommand() {
        let path = ("\(NSHomeDirectory())/.local/state/desktop-switch/cmd" as NSString).expandingTildeInPath
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var layer = "", screenSpec = ""
        for kv in line.split(separator: ";") {
            let parts = kv.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]), val = String(parts[1])
            if key == "layer" { layer = val }
            if key == "screen" { screenSpec = val }
        }
        let iShouldShow = (layer == "caldash")
        let targets: [Int] = (screenSpec == "all") ? Array(windows.indices) : windowIndices(matching: screenSpec)
        for idx in targets {
            if iShouldShow { windows[idx].orderFrontRegardless() }
            else           { windows[idx].orderOut(nil) }
        }
        print("[caldash] cmd layer=\(layer) screen=\(screenSpec) → \(iShouldShow ? "show" : "hide") \(targets.count) window(s)")
    }

    // M1: ポップアップ/新規窓を同 view に流す（サインイン用）。無人常駐では Google 一族のみ許可。
    func webView(_ w: WKWebView, createWebViewWith cfg: WKWebViewConfiguration,
                 for act: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = act.request.url, (!WALLPAPER || isGoogleHost(u.host)) { w.load(act.request) }
        return nil
    }
    // M1: 無人常駐では Google 一族以外の http(s) 遷移を遮断（認証 view の乗っ取り防止）。
    func webView(_ w: WKWebView, decidePolicyFor act: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if WALLPAPER, let u = act.request.url,
           (u.scheme == "http" || u.scheme == "https"), !isGoogleHost(u.host) {
            print("[caldash] blocked non-Google nav: \(u.absoluteString)")
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
        print("[caldash] FAIL: \(e.localizedDescription)")
    }
    // desktop-switch の SIGUSR2 で window を orderOut するとここが呼ばれて終了→launchd 再起動
    // ループに入るため、wallpaper mode では false を返して常駐継続。interactive では終了して OK。
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { !WALLPAPER }
}

setvbuf(stdout, nil, _IONBF, 0)
loadConfig()
let app = NSApplication.shared
app.setActivationPolicy(WALLPAPER ? .accessory : .regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

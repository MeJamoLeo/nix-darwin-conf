// caldash-live — カレンダー・ダッシュボード（本体 Google カレンダー×5面）
// 本体アプリを WKWebView で"最上位"ロード（iframe でないので X-Frame-Options 回避）。
// 全面が .default() データストア共有 → ログイン1回で全面認証・再起動で永続（実測済み）。
//
// レイアウト（5面）: 今日を左の縦長カラム、右を 2×2（今週/来週・今月/来月）。
//   ┌───────┬───────┬───────┐
//   │       │ 今週   │ 来週   │   ← 来週で「次の月曜」も見える（週ビュー日曜起点問題の解）
//   │ 今日   ├───────┼───────┤
//   │(縦長) │ 今月   │ 来月   │
//   └───────┴───────┴───────┘
//
// モード: （無フラグ）interactive=通常窓・ログイン用 / --wallpaper=常在面（アイコン裏・透過・全Space・無人）
// 設定: ~/calendar-dashboard/caldash-config.json（env CALDASH_CONFIG で上書き）。
//       todayWidth / rightCols / rightRows / gap / zoom / account(u/N) / tz。
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
let HIDE_CHROME_CSS = """
[role='banner'] { display: none !important; }
[role='main'] {
  position: fixed !important;
  inset: 0 !important;
  width: 100vw !important;
  height: 100vh !important;
  z-index: 999999 !important;
  background: #000 !important;
}
html, body { overflow: hidden !important; margin: 0 !important; padding: 0 !important; }
"""

// ---- 設定（既定値。config で上書き）----
var ACCOUNT = 0
var TZ_ID   = "America/Chicago"
var TODAY_W: CGFloat = 0.24          // 今日カラムの幅（画面比）
var RCOLS: [CGFloat] = [0.5, 0.5]    // 右エリアの左右比
var RROWS: [CGFloat] = [0.5, 0.5]    // 右エリアの上下比
var GAP: CGFloat = 6
var ZOOM: CGFloat = 0.75             // 全体 pageZoom（<1 で文字を小さく＝密度↑）
var WEEK_ZOOM: CGFloat = 0.5         // 今週/来週だけ更に圧縮（1日 0-24 時をスクロール無しで収める用）
// 解像度スケール式（referenceWidth が config にあると式モード起動＝main モニタ幅で自動追随）。
// 例: baseZoom=0.9 referenceWidth=2560 → 2560幅で 0.9・3840幅で ~0.735・5120幅で ~0.636（sqrt ダンパー）。
// 現画面幅の変化（モニタ挿抜・SetResolution）は didChangeScreenParametersNotification で購読して再計算。
var BASE_ZOOM: CGFloat? = nil
var BASE_WEEK_ZOOM: CGFloat? = nil
var REFERENCE_WIDTH: CGFloat? = nil

struct Config: Codable {
    var todayWidth: Double?; var rightCols: [Double]?; var rightRows: [Double]?
    var gap: Double?; var zoom: Double?; var weekZoom: Double?
    var baseZoom: Double?; var baseWeekZoom: Double?; var referenceWidth: Double?
    var account: Int?; var tz: String?
}
func loadConfig() {
    let path = ProcessInfo.processInfo.environment["CALDASH_CONFIG"]
        ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("calendar-dashboard/caldash-config.json").path
    guard let data = FileManager.default.contents(atPath: path),
          let c = try? JSONDecoder().decode(Config.self, from: data) else { return }
    if let v = c.todayWidth { TODAY_W = CGFloat(v) }
    if let v = c.rightCols, v.count == 2 { RCOLS = v.map { CGFloat($0) } }
    if let v = c.rightRows, v.count == 2 { RROWS = v.map { CGFloat($0) } }
    if let v = c.gap { GAP = CGFloat(v) }
    if let v = c.zoom { ZOOM = CGFloat(v) }
    if let v = c.weekZoom { WEEK_ZOOM = CGFloat(v) }
    if let v = c.baseZoom { BASE_ZOOM = CGFloat(v) }
    if let v = c.baseWeekZoom { BASE_WEEK_ZOOM = CGFloat(v) }
    if let v = c.referenceWidth { REFERENCE_WIDTH = CGFloat(v) }
    if let v = c.account { ACCOUNT = v }
    if let v = c.tz { TZ_ID = v }
    print("[caldash] config: todayW=\(TODAY_W) rcols=\(RCOLS) rrows=\(RROWS) gap=\(GAP) zoom=\(ZOOM) weekZoom=\(WEEK_ZOOM) u/\(ACCOUNT) \(TZ_ID)")
    if let ref = REFERENCE_WIDTH {
        print("[caldash] formula: baseZoom=\(BASE_ZOOM ?? ZOOM) baseWeekZoom=\(BASE_WEEK_ZOOM ?? WEEK_ZOOM) referenceWidth=\(ref)")
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
func paneURLs() -> [String] {
    let base = "https://calendar.google.com/calendar/u/\(ACCOUNT)/r"
    let (ny, nm) = nextMonthYM()
    let (wy, wm, wd) = nextWeekYMD()
    return [
        "\(base)/day",                     // 今日
        "\(base)/week",                    // 今週
        "\(base)/week/\(wy)/\(wm)/\(wd)",  // 来週
        "\(base)/month",                   // 今月
        "\(base)/month/\(ny)/\(nm)/1"      // 来月
    ]
}

// Google 一族のホストか（M1: 無人常駐で認証 view を外部 URL に飛ばさせない allowlist）
func isGoogleHost(_ host: String?) -> Bool {
    guard let h = host else { return true }
    let owned = ["google.com", "gstatic.com", "googleapis.com", "googleusercontent.com", "youtube.com"]
    return owned.contains { h == $0 || h.hasSuffix("." + $0) }
}

// 今日=左縦長カラム、右=2×2。isFlipped=true で左上原点。
final class GridView: NSView {
    var panes: [NSView] = []
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        guard panes.count == 5 else { return }
        let W = bounds.width, H = bounds.height
        let lw = W * TODAY_W
        let rx = lw + GAP
        let rw = max(0, W - rx)
        panes[0].frame = NSRect(x: 0, y: 0, width: lw, height: H)          // 今日（左フル高）
        let cw0 = (rw - GAP) * RCOLS[0], cw1 = (rw - GAP) * RCOLS[1]
        let rh0 = (H - GAP) * RROWS[0], rh1 = (H - GAP) * RROWS[1]
        panes[1].frame = NSRect(x: rx,           y: 0,         width: cw0, height: rh0) // 今週
        panes[2].frame = NSRect(x: rx + cw0 + GAP, y: 0,        width: cw1, height: rh0) // 来週
        panes[3].frame = NSRect(x: rx,           y: rh0 + GAP, width: cw0, height: rh1) // 今月
        panes[4].frame = NSRect(x: rx + cw0 + GAP, y: rh0 + GAP, width: cw1, height: rh1) // 来月
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var grid: GridView!
    var webs: [WKWebView] = []
    let store = WKWebsiteDataStore.default()   // ログイン共有＆永続（実測済み）

    // 式モード時の現行 zoom（画面変化時に再計算＝式が無ければ config の静的値のまま不変）
    var currentZoom: CGFloat = 0.75
    var currentWeekZoom: CGFloat = 0.5

    // 式モードか（REFERENCE_WIDTH 指定時のみ）
    var formulaMode: Bool { REFERENCE_WIDTH != nil }

    // 指定 screen 幅から effective zoom を算出。式 off なら config の静的値を返す。
    func computeEffectiveZooms(for screen: NSScreen) -> (CGFloat, CGFloat) {
        guard let ref = REFERENCE_WIDTH else { return (ZOOM, WEEK_ZOOM) }
        let base = BASE_ZOOM ?? ZOOM
        let baseW = BASE_WEEK_ZOOM ?? WEEK_ZOOM
        let w = screen.frame.width
        return (effectiveZoom(base: base, ref: ref, current: w),
                effectiveZoom(base: baseW, ref: ref, current: w))
    }

    func makeWeb(_ urlStr: String, zoom: CGFloat) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = store
        // M2: 無人常駐では JS の自動 window.open を禁止。ログインは gesture 起点なので interactive では許可。
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = !WALLPAPER
        // wallpaper mode 限定: 盤面だけ残す CSS を毎ロード注入（documentElement 直下なので
        // SPA の DOM 再構築で剥がれない）。interactive では UI 温存でログイン導線を確保。
        if WALLPAPER {
            let js = """
            (() => {
              if (document.getElementById('caldash-hide-chrome')) return;
              const s = document.createElement('style');
              s.id = 'caldash-hide-chrome';
              s.textContent = `\(HIDE_CHROME_CSS)`;
              (document.head || document.documentElement).appendChild(s);
            })();
            """
            let script = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            cfg.userContentController.addUserScript(script)
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
        grid = GridView(frame: .zero)
        grid.wantsLayer = true
        grid.layer?.backgroundColor = NSColor.black.cgColor
        grid.autoresizingMask = [.width, .height]
        let initialScreen = NSScreen.main ?? NSScreen.screens[0]
        (currentZoom, currentWeekZoom) = computeEffectiveZooms(for: initialScreen)
        let zooms: [CGFloat] = [currentZoom, currentWeekZoom, currentWeekZoom, currentZoom, currentZoom]  // 今日/今週/来週/今月/来月
        webs = zip(paneURLs(), zooms).map { makeWeb($0, zoom: $1) }
        grid.panes = webs
        webs.forEach { grid.addSubview($0) }
        if formulaMode {
            print("[caldash] effective zoom on width=\(initialScreen.frame.width): \(currentZoom)/\(currentWeekZoom)")
        }

        if WALLPAPER {
            let screen = initialScreen
            window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = true
            window.isOpaque = true
            window.backgroundColor = .black
            window.contentView = grid
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            print("[caldash] wallpaper mode on \(screen.frame.size)")
            // 解像度/main モニタの変化を購読して window と zoom を追随（モニタ挿抜・SetResolution 対応）。
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                self?.reapplyForCurrentScreen()
            }
        } else {
            let frame = NSRect(x: 0, y: 0, width: 1800, height: 1050)
            window = NSWindow(contentRect: frame,
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
            window.title = "caldash — 今日/今週/来週/今月/来月（--wallpaper で常在面化）"
            window.contentView = grid
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        scheduleDailyReanchor()
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
        for (i, wv) in webs.enumerated() where i < urls.count {
            if let u = URL(string: urls[i]) { wv.load(URLRequest(url: u)) }
        }
        print("[caldash] re-anchored")
    }

    // 画面変化（モニタ挿抜・main 切替・解像度変更）で window と zoom を追随。
    // wallpaper mode 専用：現状は main 1画面のみ描画（副モニタは対象外＝C1 スコープ）。
    func reapplyForCurrentScreen() {
        guard WALLPAPER else { return }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let oldFrame = window.frame
        if oldFrame != screen.frame {
            window.setFrame(screen.frame, display: true)
        }
        let (newZ, newWZ) = computeEffectiveZooms(for: screen)
        if formulaMode && (newZ != currentZoom || newWZ != currentWeekZoom) {
            currentZoom = newZ
            currentWeekZoom = newWZ
            let zooms: [CGFloat] = [newZ, newWZ, newWZ, newZ, newZ]
            for (i, wv) in webs.enumerated() where i < zooms.count {
                wv.pageZoom = zooms[i]
            }
            print("[caldash] screen changed: width=\(screen.frame.width) → zoom=\(newZ)/\(newWZ)")
        } else if oldFrame != screen.frame {
            print("[caldash] screen frame changed: \(oldFrame.size) → \(screen.frame.size)")
        }
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
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

setvbuf(stdout, nil, _IONBF, 0)
loadConfig()
let app = NSApplication.shared
app.setActivationPolicy(WALLPAPER ? .accessory : .regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

// caldash-spike — フェーズ①実現性スパイク（使い捨て）
// 目的: WKWebView 1枚＋Safari UA 詐称＋永続データストアで
//       Google 本体カレンダー(/r)に手動ログインできるか確認する。
// 判定: ログインが通り、ダークの本体カレンダー(Day/Week/Month)が出れば go。
//       "このブラウザは安全でない可能性" 等で弾かれたら no-go → UA を変えて再試行 or 撤退。
// 実行: 下記コメントのビルドコマンド参照。起動後、自分の Google で手動ログイン。
//   再起動してもログインが維持されるか（永続データストア）も確認する。

import Cocoa
import WebKit

// 実 Safari が送る安定文字列。WKWebView 既定 UA は "Version/" を欠き Google に弾かれるため明示詐称。
let SAFARI_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
let START_URL = "https://calendar.google.com/calendar/u/0/r"

class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    var window: NSWindow!
    var webView: WKWebView!

    func applicationDidFinishLaunching(_ note: Notification) {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()          // 永続: ログイン cookie をディスク保存（再起動で維持）
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 900)
        webView = WKWebView(frame: frame, configuration: cfg)
        webView.customUserAgent = SAFARI_UA        // ← UA 詐称
        webView.navigationDelegate = self
        webView.uiDelegate = self                  // ← window.open / ポップアップを拾う（(b) 無反応の主因対策）
        if #available(macOS 13.3, *) { webView.isInspectable = true }  // デバッグ: Safari の開発メニューから覗ける
        webView.load(URLRequest(url: URL(string: START_URL)!))

        window = NSWindow(contentRect: frame,
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "caldash spike — Google にログインして本体カレンダーが出るか確認"
        window.contentView = webView
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)
        NSApp.activate(ignoringOtherApps: true)
    }

    // ★ (b) 対策: window.open / target=_blank を"同じ WebView"に流し込む（未実装だと黙って捨てられ無反応）
    func webView(_ w: WKWebView, createWebViewWith cfg: WKWebViewConfiguration,
                 for act: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = act.request.url { print("[caldash-spike] popup→same-view: \(u.absoluteString)"); w.load(act.request) }
        return nil
    }

    // どこで止まるか可視化（ナビゲーションを全部ログ）
    func webView(_ w: WKWebView, decidePolicyFor act: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        print("[caldash-spike] nav→ \(act.request.url?.absoluteString ?? "?")")
        decisionHandler(.allow)
    }
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) {
        print("[caldash-spike] loaded: \(w.url?.absoluteString ?? "?")  title=\(w.title ?? "?")")
    }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) {
        print("[caldash-spike] FAIL: \(e.localizedDescription)")
    }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
        print("[caldash-spike] FAIL(provisional): \(e.localizedDescription)")
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)   // メニュー/キー入力を受ける（ログイン入力のため）
let delegate = AppDelegate()
app.delegate = delegate
app.run()

/* ── ビルド（cp-dashboard と同じ env -i 隔離。nix の SDKROOT 汚染で stdlib を見失う件の回避） ──
   /usr/bin/env -i HOME="$HOME" PATH="/usr/bin:/bin" \
     SDKROOT="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)" \
     /usr/bin/xcrun swiftc -O -o /tmp/caldash-spike \
     "$HOME/Forge/nix-darwin-conf/modules/custom/calendar-dashboard/dashboard/swift/caldash-spike.swift"
   実行:  /tmp/caldash-spike
*/

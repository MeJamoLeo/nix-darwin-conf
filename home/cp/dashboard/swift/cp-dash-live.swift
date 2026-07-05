// cp-dash-live — CP ダッシュボードのライブ層。
// 全ディスプレイのデスクトップレベル（壁紙と同層・アイコンより下）に WKWebView を常駐させ、
// web/inject.js の mtime を1秒ポーリングして変化したら reload する。
// x1nano 版（GTK4+WebKit+layer-shell の背景レイヤー描画）の macOS 対応物。
// 終了 = プロセス kill のみ。システム状態は何も変えない。
import AppKit
import WebKit

final class LiveLayer: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var webViews: [WKWebView] = []
    private var lastMTime = Date.distantPast

    private let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("cp-dashboard")
    private var htmlURL: URL { root.appendingPathComponent("web/draft-v1.html") }
    private var injectURL: URL { root.appendingPathComponent("web/inject.js") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard FileManager.default.fileExists(atPath: htmlURL.path) else {
            FileHandle.standardError.write(Data("error: \(htmlURL.path) not found\n".utf8))
            NSApp.terminate(nil)
            return
        }
        for screen in NSScreen.screens {
            let win = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                               backing: .buffered, defer: false)
            win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            win.ignoresMouseEvents = true
            win.isOpaque = true
            // 盤面背景色 (--bg #020404) でレターボックス。壁紙 fit と同じ見た目に。
            win.backgroundColor = NSColor(srgbRed: 0x02 / 255.0, green: 0x04 / 255.0,
                                          blue: 0x04 / 255.0, alpha: 1)
            win.setFrame(screen.frame, display: true)

            // 盤面は 16:9 前提でチューニング済み。window(=画面)に対し縦横比 16:9 を保った
            // 最大矩形を中央に置き、余りは window 背景色で埋める（比率が違っても崩れない）。
            let b = win.contentView!.bounds
            let fitW = min(b.width, b.height * 16.0 / 9.0)
            let fitH = fitW * 9.0 / 16.0
            let frame = NSRect(x: (b.width - fitW) / 2, y: (b.height - fitH) / 2,
                               width: fitW, height: fitH)
            let webView = WKWebView(frame: frame)
            webView.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
            win.contentView!.addSubview(webView)
            webView.loadFileURL(htmlURL, allowingReadAccessTo: root)

            win.orderFrontRegardless()
            windows.append(win)
            webViews.append(webView)
        }
        lastMTime = injectMTime()
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollInject()
        }
        print("[cp-dash-live] up: \(windows.count) screen(s), watching \(injectURL.path)")
    }

    private var draftDataURL: URL { root.appendingPathComponent("web/draft-data.js") }

    private func injectMTime() -> Date {
        // draft-v1 が実際に読むのは draft-data.js。inject.js は 30分サイクルの
        // 互換シグナルとして残す（どちらか新しい方で reload）。
        return [injectURL, draftDataURL].compactMap {
            (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date
        }.max() ?? .distantPast
    }

    private func pollInject() {
        let mtime = injectMTime()
        guard mtime > lastMTime else { return }
        lastMTime = mtime
        for webView in webViews {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: root)
        }
        print("[cp-dash-live] inject.js changed — reloaded")
    }
}

setvbuf(stdout, nil, _IONBF, 0)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = LiveLayer()
app.delegate = delegate
app.run()

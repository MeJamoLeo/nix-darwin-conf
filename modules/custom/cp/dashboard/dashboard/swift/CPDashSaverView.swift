// CPDashSaver — CP ダッシュボードの最新レンダリング PNG を表示する最小 .saver。
// WebKit 不使用（WVSS は macOS 26 で黒画面 = upstream issue #97）。
// sandbox 対策: legacyScreenSaver の HOME はコンテナに remap されるため、
// update.sh がコンテナ内 (~/cp-dash/wall.png) へ PNG をコピーし、ここはそれを読む。
//
// Tahoe (macOS 26) の legacyScreenSaver 既知バグ対策
// （wiki: macos-screensaver-requirements / ScreenSaverMinimal の定番回避を踏襲）:
// - インスタンス蓄積 (FB19204084): willstop 通知 → 2秒後 exit(0)
// - isPreview 誤報告 (FB18697726): CGSSessionScreenIsLocked で自前判定
// - stopAnimation が呼ばれない: animateOneFrame に依存せず自前 Timer
import ScreenSaver
import AppKit

private func isScreenLocked() -> Bool {
    guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
    return (d["CGSSessionScreenIsLocked"] as? Bool) ?? false
}

@objc(CPDashSaverView)
public final class CPDashSaverView: ScreenSaverView {
    private var image: NSImage?
    private var lastMTime = Date.distantPast
    private var reloadTimer: Timer?
    private var willStopObserver: NSObjectProtocol?
    private var actualIsPreview = false

    private var imagePath: String {
        NSHomeDirectory() + "/cp-dash/wall.png"
    }

    public override init?(frame: NSRect, isPreview: Bool) {
        // Tahoe は isPreview が信用できない: ロック中=実走行、非ロック=プレビュー
        if #available(macOS 26.0, *) {
            actualIsPreview = !isScreenLocked()
        } else {
            actualIsPreview = isPreview
        }
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        animationTimeInterval = 5.0
        reloadIfChanged()
        // 実走行のみ: willstop で確実にプロセスを終わらせる（蓄積バグ対策）
        if !actualIsPreview {
            willStopObserver = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("com.apple.screensaver.willstop"),
                object: nil, queue: .main
            ) { [weak self] _ in
                self?.reloadTimer?.invalidate()
                self?.reloadTimer = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { exit(0) }
            }
        }
    }

    public override func startAnimation() {
        super.startAnimation()
        guard reloadTimer == nil else { return }
        reloadTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.reloadIfChanged()
        }
    }

    public override func stopAnimation() {
        super.stopAnimation()
        reloadTimer?.invalidate()
        reloadTimer = nil
    }

    deinit {
        reloadTimer?.invalidate()
        if let observer = willStopObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    private func reloadIfChanged() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: imagePath)
        let mtime = attrs?[.modificationDate] as? Date ?? .distantPast
        guard mtime > lastMTime else { return }
        lastMTime = mtime
        image = NSImage(contentsOfFile: imagePath)
        needsDisplay = true
    }

    public override func animateOneFrame() {
        // Tahoe では信頼できないが、呼ばれた場合の保険として残す
        reloadIfChanged()
    }

    public override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard let image else {
            let msg = "cp-dash: \(imagePath) が読めない" as NSString
            msg.draw(at: NSPoint(x: 20, y: 20), withAttributes: [
                .foregroundColor: NSColor.gray,
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            ])
            return
        }
        // アスペクト維持で全面フィット
        let iw = image.size.width, ih = image.size.height
        guard iw > 0, ih > 0 else { return }
        let scale = min(bounds.width / iw, bounds.height / ih)
        let w = iw * scale, h = ih * scale
        let target = NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2,
                            width: w, height: h)
        image.draw(in: target, from: .zero, operation: .copy, fraction: 1.0)
    }
}

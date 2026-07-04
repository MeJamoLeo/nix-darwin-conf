// set-wallpaper — NSWorkspace でディスプレイごとに壁紙を設定する。
// Apple Events を使わないので Automation (TCC) 許可が不要 = launchd から無人で動く。
//
// 方針（2026-07-03）: 盤面は 16:9 で一度だけ描き、render-wallpaper.sh が各画面の
// native 解像度へ「縦横比保持で fit＋背景色レターボックス」した PNG を用意する。
// ここはその native サイズ済み PNG を画面ごとに 1:1 で貼るだけ（歪みも余白暴れもなし）。
//
// 使い方:
//   set-wallpaper --list             各画面の native 解像度を1行ずつ出力（NSScreen 順）
//   set-wallpaper <img0> <img1> …    画面 i に imgi（足りない分は最後の画像を流用）
import AppKit

let args = Array(CommandLine.arguments.dropFirst())

if args.first == "--list" {
    for s in NSScreen.screens {
        let scale = s.backingScaleFactor
        let w = Int((s.frame.width * scale).rounded())
        let h = Int((s.frame.height * scale).rounded())
        print("\(w) \(h)")
    }
    exit(0)
}

guard !args.isEmpty else {
    FileHandle.standardError.write(Data("usage: set-wallpaper [--list] <image>...\n".utf8))
    exit(64)
}

let paths = args
var failed = false
for (i, screen) in NSScreen.screens.enumerated() {
    let path = i < paths.count ? paths[i] : paths[paths.count - 1]
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
        FileHandle.standardError.write(Data("error: no such file: \(url.path)\n".utf8))
        failed = true
        continue
    }
    do {
        try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
    } catch {
        FileHandle.standardError.write(Data("error: \(screen.localizedName): \(error.localizedDescription)\n".utf8))
        failed = true
    }
}
exit(failed ? 1 : 0)

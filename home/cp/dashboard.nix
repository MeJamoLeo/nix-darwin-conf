{ config, pkgs, lib, ... }:
let
  home = config.home.homeDirectory;
  root = "${home}/cp-dashboard";          # runtime working dir (mutable: out/, web/inject.js)
  saver = "${home}/Library/Screen Savers/CPDashSaver.saver";
  # launchd の PATH（agent はシェル PATH を継承しない）。python3 と素の coreutils だけ要る。
  runtimePath = "${pkgs.python3}/bin:/usr/bin:/bin";
in
{
  # CP ダッシュボードを macOS に常駐（壁紙 / ライブ層 / スクリーンセーバー）。
  # 正典アセットは ./dashboard/（repo 内）。activation で ~/cp-dashboard へ配置し、
  # Swift 3本を機体の swiftc(CLT) でビルド、launchd 2本を宣言的に管理する。
  # 詳細設計: vault/wiki/1_Projects/cp-dashboard-macos。

  #--- 旧・手置き plist の takeover ------------------------------------------
  # home-manager が launchd.agents を symlink で張る前に、imperative 時代の
  # 実ファイル plist を bootout+削除しておく（無いと "would be clobbered" で失敗）。
  home.activation.cpDashboardTakeover =
    lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      for label in com.treo.cp-dashboard com.treo.cp-dashboard-live com.treo.cp-dashboard-stopwatch; do
        f="${home}/Library/LaunchAgents/$label.plist"
        if [ -f "$f" ] && [ ! -L "$f" ]; then
          /bin/launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
          rm -f "$f"
        fi
      done
    '';

  #--- アセット配置 + Swift ビルド -------------------------------------------
  home.activation.cpDashboardDeploy =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      src="${./dashboard}"
      dst="${root}"
      mkdir -p "$dst/out"

      # repo を source of truth として書き換え可能コピーを配置（out/ は runtime 状態なので温存）
      for d in bin swift upstream web; do
        rm -rf "$dst/$d"
        cp -R "$src/$d" "$dst/$d"
        chmod -R u+w "$dst/$d"
      done
      cp -f "$src/watchlist.json" "$dst/watchlist.json"
      chmod u+w "$dst/watchlist.json"

      # Swift 3本を機体の swiftc(CLT/Xcode) でビルド。CLT 不在なら switch 全体は殺さず警告のみ。
      # 注: nix activation の環境変数 (SDKROOT 等が nix 側を向く) をそのまま渡すと
      # swiftc が stdlib を見失う (unable to load standard library) ため、env -i で隔離する。
      if /usr/bin/xcrun -f swiftc >/dev/null 2>&1; then
        swift_build() {
          /usr/bin/env -i HOME="$HOME" PATH="/usr/bin:/bin" \
            SDKROOT="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)" \
            /usr/bin/xcrun swiftc "$@"
        }
        swift_build -O -o "$dst/bin/set-wallpaper" "$dst/swift/set-wallpaper.swift"
        swift_build -O -o "$dst/bin/cp-dash-live"  "$dst/swift/cp-dash-live.swift"

        # スクリーンセーバー .saver バンドル
        swift_build -parse-as-library -emit-library -module-name CPDashSaver \
          -framework ScreenSaver -framework AppKit \
          -o "$dst/out/CPDashSaver.dylib" "$dst/swift/CPDashSaverView.swift"
        mkdir -p "${saver}/Contents/MacOS"
        cp -f "$dst/out/CPDashSaver.dylib" "${saver}/Contents/MacOS/CPDashSaver"
        cat > "${saver}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>net.treo.cpdashsaver</string>
<key>CFBundleName</key><string>CPDashSaver</string>
<key>CFBundleExecutable</key><string>CPDashSaver</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>NSPrincipalClass</key><string>CPDashSaverView</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
        /usr/bin/codesign -s - -f "${saver}" 2>/dev/null || true
      else
        echo "warning(cp-dashboard): swiftc(CLT) 不在 — Swift ビルドをスキップ。'xcode-select --install' 後に再 switch。" >&2
      fi
    '';

  #--- launchd エージェント2本（宣言化）------------------------------------
  launchd.agents."com.treo.cp-dashboard" = {
    enable = true;
    config = {
      ProgramArguments = [ "${root}/bin/update.sh" ];
      StartInterval = 1800;          # 30分ごと
      RunAtLoad = true;
      EnvironmentVariables.PATH = runtimePath;
      StandardOutPath = "${root}/out/launchd.log";
      StandardErrorPath = "${root}/out/launchd.log";
    };
  };

  launchd.agents."com.treo.cp-dashboard-live" = {
    enable = true;
    config = {
      ProgramArguments = [ "${root}/bin/cp-dash-live" ];
      KeepAlive = true;              # 落ちても復活
      RunAtLoad = true;
      StandardOutPath = "${root}/out/live.log";
      StandardErrorPath = "${root}/out/live.log";
    };
  };

  # SOLVE STOPWATCH (#36): アイドル時は即終了の軽量パス。走行中のみ kenkoooo を
  # 差分ポーリングして初 AC で凍結する（cp-go からも1回キックされる＝秒速反応）。
  launchd.agents."com.treo.cp-dashboard-stopwatch" = {
    enable = true;
    config = {
      ProgramArguments = [ "${pkgs.python3}/bin/python3" "${root}/upstream/stopwatch_poll.py" ];
      StartInterval = 60;
      RunAtLoad = true;
      EnvironmentVariables.PATH = runtimePath;
      StandardOutPath = "${root}/out/stopwatch.log";
      StandardErrorPath = "${root}/out/stopwatch.log";
    };
  };
}

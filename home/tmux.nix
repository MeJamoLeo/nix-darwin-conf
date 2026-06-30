{ pkgs, lib, ... }:
# tmux 設定（home-manager で宣言的に管理）。
#
# 【このファイルの位置づけ】
#   全マシン（mac 2台 + NixOS laptop）で「同じ tmux」を実現するための単一源。
#   mac 2台は nix-darwin-conf の home/ を共有するのでこのファイルで即統一される。
#   NixOS(nixos-cp) は flake input でこのモジュールを取り込んで同じ設定を得る。
#   将来 monorepo を立てたら、このファイルがそのまま home/common/tmux.nix になる。
#
# 【プラグインは nix 管理＝TPM 不要】
#   home-manager はプラグインを run-shell として直接 config に書き出すので、
#   TPM の bootstrap（git clone / prefix+I）は一切不要。flake.lock で版も固定される。
{
  programs.tmux = {
    enable = true;

    # prefix: 既定の C-b は押しにくいので C-t に変更。
    #   shadow するのは zsh emacs モードの transpose-chars（ほぼ使わない）だけ。
    #   ※将来 programs.fzf の zsh 統合を有効化すると fzf が Ctrl-T を奪うので、
    #     その時は fzf 側のキーを Alt-T 等に逃がすこと。
    prefix = "C-t";

    baseIndex = 1;          # window/pane を 1 始まりに（キーボード左から順＝0 より押しやすい）
    escapeTime = 0;         # ESC 入力の遅延を 0 に（vim の ESC が機敏になる）
    historyLimit = 100000;  # スクロールバック行数（既定 2000 は少なすぎ）
    keyMode = "vi";         # copy-mode を vi キーバインドに（nvim ユーザ向け）
    mouse = true;           # マウスでペイン選択・リサイズ・スクロール可
    terminal = "tmux-256color";  # truecolor の前提（下の terminal-overrides と対）

    # tmux-sensible を config 先頭で自動読み込み。未設定の項目だけ無難な既定を入れる
    # 安全なベース。これが sensible 本体を読むので plugins への併記は不要（二重ロード回避）。
    sensibleOnTop = true;

    plugins = with pkgs.tmuxPlugins; [
      # vim-tmux-navigator: C-h/j/k/l で vim の分割と tmux のペインを“境目なく”移動。
      #   nvim 側にも同名プラグインを入れると、vim split と tmux pane を同じキーで往来できる。
      vim-tmux-navigator

      # yank: copy-mode で選択したテキストをシステムクリップボードへ送る。
      #   実際のコピー先コマンドは下の extraConfig で OS 別に指定（pbcopy / wl-copy）。
      yank

      # ── テーマは resurrect/continuum より“前”に置く（順序ルール） ──
      #   status-line を書き換えるプラグインを後に置くと restore が壊れて
      #   「プラグイン未インストール」状態に見えるため。
      {
        # catppuccin: status bar をテーマ化。mocha=暗めの定番フレーバー。
        plugin = catppuccin;
        extraConfig = "set -g @catppuccin_flavour 'mocha'";
      }

      # resurrect: セッション（window/pane 構成・作業ディレクトリ）を手動で保存/復元。
      #   保存= prefix + C-s / 復元= prefix + C-r。
      #   capture-pane-contents='on' でペインの中身も一緒に保存する。
      {
        plugin = resurrect;
        extraConfig = "set -g @resurrect-capture-pane-contents 'on'";
      }

      # continuum: resurrect の上に乗る自動化。一定間隔で自動保存し、tmux 起動時に自動復元。
      #   restore='on'      = tmux サーバ起動時に直前のセッションを自動で戻す
      #   save-interval='15'= 15 分ごとに自動保存
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '15'
        '';
      }
    ];

    extraConfig = ''
      # truecolor(24bit): terminal を 256color にした上で、この override で外側端末に
      #   24bit を通す。外側端末は iTerm2/Ghostty/WezTerm 等（truecolor 対応）が前提。
      set -ga terminal-overrides ",xterm-256color:Tc"

      # window を閉じたら番号を詰め直す（1,2,4 → 1,2,3）。baseIndex=1 と相性が良い。
      set -g renumber-windows on

      # 端末ネイティブのクリップボード連携（OSC52）。対応端末ならこれだけで効く。
      set -g set-clipboard on

      # copy-mode で y を押したらシステムクリップボードへコピー（OS でコマンドが違うので分岐）。
      ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
        bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "pbcopy"
      ''}${lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
        bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "wl-copy"
      ''}
    '';
  };

  # Linux(Wayland/sway) では wl-copy 本体が必要。mac は pbcopy が OS 標準なので不要。
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.wl-clipboard ];
}

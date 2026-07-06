{
  description = "Nix for macOS configuration";

  ##################################################################################################################
  #
  # Want to know Nix in details? Looking for a beginner-friendly tutorial?
  # Check out https://github.com/ryan4yin/nixos-and-flakes-book !
  #
  ##################################################################################################################

  # the nixConfig here only affects the flake itself, not the system configuration!
  nixConfig = {
    # Use this to add custom substituters if needed; keeping commented preserves history.
    # substituters = [
    #   # Query the mirror of USTC first, and then the official cache.
    #   "https://mirrors.ustc.edu.cn/nix-channels/store"
    #   "https://cache.nixos.org"
    # ];
  };

  # This is the standard format for flake.nix. `inputs` are the dependencies of the flake,
  # Each item in `inputs` will be passed as a parameter to the `outputs` function after being pulled and built.
  inputs = {
    # nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    # home-manager, used for managing user configuration
    home-manager = {
      # The `follows` keyword in inputs is used for inheritance.
      # Here, `inputs.nixpkgs` of home-manager is kept consistent with the `inputs.nixpkgs` of the current flake,
      # to avoid problems caused by different versions of nixpkgs dependencies.
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    neru = {
      url = "github:y3owk1n/neru";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    # herdr: tmux ライクな “エージェント対応” ターミナルマルチプレクサ（Rust 単一バイナリ）。
    #   nixpkgs 未収録なので flake input として取り込み、overlay で pkgs.herdr を供給する
    #   （neru と同じ作法）。follows で nixpkgs を揃えて重複ビルド/eval コストを抑える。
    herdr = {
      url = "github:ogulcancelik/herdr";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
  };

  # The `outputs` function will return all the build results of the flake.
  # A flake can have many use cases and different types of outputs,
  # parameters in `outputs` are defined in `inputs` and can be referenced by their names.
  # However, `self` is an exception, this special parameter points to the `outputs` itself (self-reference)
  # The `@` syntax here is used to alias the attribute set of the inputs's parameter, making it convenient to use inside the function.
  outputs = inputs @ {
    self,
    nixpkgs,
    darwin,
    home-manager,
    ...
  }: let
    username = "treo";
    system = "aarch64-darwin";

    mkDarwinConfig = hostname: let
      specialArgs =
        inputs
        // {
          inherit username hostname;
        };
    in
      darwin.lib.darwinSystem {
        inherit system specialArgs;
        modules = [
          {nixpkgs.overlays = [inputs.neru.overlays.default inputs.herdr.overlays.default];}

          ./modules/nix-core.nix
          ./modules/system.nix
          ./modules/apps.nix
          ./modules/host-users.nix
          ./modules/latex.nix
          ./modules/remote-access.nix
          # ./modules/network-block.nix
          ./modules/school/txst.nix
          ./modules/courses/cs3354.nix

          # dejima (使い捨て VM) のみ mas を無効化。
          # App Store 経由アプリは Apple ID ログインが必要で、headless な使い捨て
          # VM では毎回サインインするのが面倒なため空にする（casks/brews は入る）。
          ({
            lib,
            hostname,
            ...
          }:
            lib.mkIf (hostname == "dejima") {
              # App Store 経由アプリは Apple ID ログインが要るので空にする。
              homebrew.masApps = lib.mkForce {};

              # dejima は headless の使い捨て島。Homebrew の GUI アプリ(~30個)は
              #  (1) 50GB の VM ディスクに収まらず (2) headless では起動して使えない
              # ので、dejima 限定で Homebrew activation ごと無効化する。
              # → switch が緑・数十秒、base が軽い。casks/brews の宣言は実機用に
              #   config に残るが dejima では実行しない（ogasawara/tanegashima は無変更）。
              homebrew.enable = lib.mkForce false;

              # tart の NAT は MTU ブラックホール（小パケットは通るが TLS の大パケットが
              # 落ちる）。en0 の MTU を 1400 に下げると外向き TLS が通る。
              # postActivation は boot 時に走らない/早すぎるので、専用 LaunchDaemon で
              # 「起動ごと・en0 が上がるまでリトライ」で確実に下げる（switch 時も
              # RunAtLoad で再発火）。→ respin 後も自動で効く自己修復。
              launchd.daemons.dejima-mtu = {
                script = ''
                  for _ in $(seq 1 15); do
                    /sbin/ifconfig en0 mtu 1400 && exit 0
                    sleep 2
                  done
                '';
                serviceConfig = {
                  RunAtLoad = true;
                  StandardErrorPath = "/var/log/dejima-mtu.log";
                };
              };
            })

          # home manager
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = specialArgs;
            home-manager.users.${username} = import ./home;
          }
        ];
      };
  in {
    darwinConfigurations = {
      ogasawara = mkDarwinConfig "ogasawara"; # Mac mini M4
      tanegashima = mkDarwinConfig "tanegashima"; # MacBook Air M1
      dejima = mkDarwinConfig "dejima"; # 使い捨て VM (sandbox) — mas 無効
    };

    # 全マシンで共有する home-manager モジュール（単一源）。
    # mac 2台は home/default.nix 経由で取り込み済み。
    # NixOS(nixos-cp) はこの flake を input にして homeModules.tmux を import する。
    # system 非依存（純粋な module 関数）なので Linux/Darwin 双方で評価できる。
    homeModules.tmux = import ./home/tmux.nix;

    # デバイス公開鍵台帳（単一源）。詳細は keys.nix のコメント参照。
    # NixOS(x1nano) からは inputs.nix-darwin-conf.sshKeys.<device> で参照して
    # authorizedKeys に選択する（homeModules.tmux と同じ共有パターン）。
    sshKeys = import ./keys.nix;

    # nix code formatter
    formatter.${system} = nixpkgs.legacyPackages.${system}.alejandra;
  };
}

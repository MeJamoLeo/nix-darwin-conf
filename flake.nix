{
  description = "Nix for macOS configuration";

  # the nixConfig here only affects the flake itself, not the system configuration!
  nixConfig = {
    # Use this to add custom substituters if needed; keeping commented preserves history.
    # substituters = [
    #   # Query the mirror of USTC first, and then the official cache.
    #   "https://mirrors.ustc.edu.cn/nix-channels/store"
    #   "https://cache.nixos.org"
    # ];
  };

  inputs = {
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    # git だけ安定版にピン留めするための独立 nixpkgs。
    #   unstable の git 2.54.0 は「長い unicode ファイル名」を含む作業ツリーの
    #   untracked 走査（git status --untracked-files=all / git ls-files -o）で
    #   SIGTRAP（スタック保護が検知するバッファオーバーフロー）を起こすリグレッション。
    #   hunk・git-crypt も内部で untracked 走査を呼ぶため巻き添えで落ちる。
    #   nixos-25.05 の git 2.50.1 は無傷なので、modules/git/home.nix の
    #   programs.git.package でこれを参照する。2.54.x で修正されたらこの input ごと外す。
    #   （follows を張らない＝git を古い版に固定するのが目的なので独立させる）
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.05";

    # home-manager, used for managing user configuration
    home-manager = {
      # `follows` で nixpkgs を親と揃え、依存バージョン差異による問題を避ける。
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

  ##################################################################################
  #
  #  構造の地図（詳細ルールは各ディレクトリの中身が自己記述する）：
  #
  #    hosts/<name>.nix       機体 = 1台1ファイル。profile を import し差分だけ書く
  #    profiles/<role>.nix    役割 = トピックの束（システム層 + ユーザー層の配線）
  #    modules/<topic>/       1 関心事 = 1 ディレクトリ。ファイル名が適用層を宣言：
  #                             darwin.nix = nix-darwin 層 / home.nix = home-manager 層
  #                             （将来 NixOS を足すなら nixos.nix を同居させる）
  #    modules/_archive/      退役トピック。復帰は profile に import 1行
  #    keys.nix               デバイス公開鍵台帳（◆外部公開、下の sshKeys）
  #
  ##################################################################################
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

          # 機体ファイル（profile の import と機体固有差分はこの中）
          ./hosts/${hostname}.nix

          # home-manager の土台配線。ユーザーのモジュール選択は profile 側が行う
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            # HM が新たに管理し始めたファイル（例: ~/.zprofile）と既存の
            # 管理外ファイルが衝突したとき、エラーで止めず .hm-backup に退避する
            home-manager.backupFileExtension = "hm-backup";
            home-manager.extraSpecialArgs = specialArgs;
          }
        ];
      };
  in {
    darwinConfigurations = {
      ogasawara = mkDarwinConfig "ogasawara"; # Mac mini M4
      tanegashima = mkDarwinConfig "tanegashima"; # MacBook Air M1
      dejima = mkDarwinConfig "dejima"; # 使い捨て VM (sandbox)
    };

    # ◆ 外部公開 output（他リポジトリとの契約。パスを動かしても output 名は変えない）

    # 全マシンで共有する home-manager モジュール（単一源）。
    # mac 3台は profiles/mac-workstation.nix 経由で取り込み済み。
    # NixOS(nixos-cp) はこの flake を input にして homeModules.tmux を import する。
    # system 非依存（純粋な module 関数）なので Linux/Darwin 双方で評価できる。
    homeModules.tmux = import ./modules/tmux/home.nix;

    # デバイス公開鍵台帳（単一源）。詳細は keys.nix のコメント参照。
    # NixOS(x1nano) からは inputs.nix-darwin-conf.sshKeys.<device> で参照して
    # authorizedKeys に選択する（homeModules.tmux と同じ共有パターン）。
    sshKeys = import ./keys.nix;

    # nix code formatter
    formatter.${system} = nixpkgs.legacyPackages.${system}.alejandra;
  };
}

{
  pkgs,
  lib,
  ...
}: let
  # claudefm：Anthropic の Claude FM（YouTube の 24 時間 lofi 配信）を、
  # ブラウザを開かずにターミナルで音だけ流す CLI。nixpkgs に無いので GitHub から組む。
  # 中身は yt-dlp と mpv を呼ぶだけなので、2つを PATH に入れて包む。
  #
  # YouTube の柵（custom/youtube-gate）との関係：2026-11-08 に hosts から YouTube を外した。
  # yt-dlp は PAC を読まないので通り、ブラウザは PAC で止まったまま。
  claudefm = pkgs.buildNpmPackage {
    pname = "claudefm";
    version = "0.1.6";

    src = pkgs.fetchFromGitHub {
      owner = "GithubAnant";
      repo = "claudefm";
      rev = "688b72fa492c5575bf16194bab647d320f2b5f48";
      hash = "sha256-1Mq8cUEnWB802j7rNbIPb+cDi2QRCXEWHEvvizhiWOM=";
    };

    npmDepsHash = "sha256-Zp/SnRtTpxEHy9sEg4lkFb6lvUFOSnqRb2ynSPVvBd4=";

    nativeBuildInputs = [pkgs.makeWrapper];

    postInstall = ''
      wrapProgram $out/bin/claudefm \
        --prefix PATH : ${lib.makeBinPath [pkgs.yt-dlp pkgs.mpv]}
    '';

    meta = {
      description = "Claude FM の YouTube 生配信を音だけターミナルで流す";
      homepage = "https://github.com/GithubAnant/claudefm";
      license = lib.licenses.mit;
      mainProgram = "claudefm";
    };
  };
in {
  home.packages = [claudefm];
}

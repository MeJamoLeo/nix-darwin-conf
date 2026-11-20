# Wallpapers for distros missing from nixpkgs, repacked as share/backgrounds (or KDE-style share/wallpapers)
# and mixed into wallpaperSources in home.nix.
#
# Sources and licences (viewed locally only; no images are stored in this repo, nothing is redistributed):
#   deepin    linuxdeepin/deepin-wallpapers 1.7.28   deepin/ and solid are UnionTech CC-BY-4.0
#             (nonfree/ is CC-BY-NC-ND and Unsplash, so skipped; mp4 skipped too)
#   opensuse  openSUSE/wallpapers (master)           CC BY / CC BY-SA per author (*/license/)
#   solus     getsolus/artwork                       CC0 / CC BY / CC BY-SA (README, Attribution)
#   garuda    garuda-wallpapers 1.1.1 (GitLab)       repo is GPL-3; per-image origin unverified
#   arch      xyproto/archlinux-wallpaper 1.6.1      png is CC0, jpg is Pixabay License
#   debian    desktop-base 13.0.4                    GPL-2+ etc. per theme (debian/copyright)
#   mint      mint-backgrounds-wilma 1.1 (Mint 22)   images are Unsplash License (Credits)
#   ubuntu    ubuntu-wallpapers-{stonking,resolute}  mostly CC-BY-SA, differs per file
#   kali      kali-wallpapers-2026 2026.3.0          GPL-3.0+, includes trademarked elements
# Manjaro, Zorin, EndeavourOS, Vanilla OS, Void and Gentoo are left out: no source could be pinned down.
{pkgs}: let
  inherit (pkgs) fetchFromGitHub fetchzip fetchurl runCommand;

  pick = name: src: dirs:
    runCommand "wallpapers-${name}" {} ''
      mkdir -p $out/share/backgrounds
      for d in ${toString dirs}; do
        for f in "${src}/$d"/*; do
          case "''${f,,}" in
            *.jpg|*.jpeg|*.png|*.webp|*.svg)
              ln -s "$f" "$out/share/backgrounds/''${d//\//-}-$(basename "$f")" ;;
          esac
        done
      done
    '';

  fromDeb = name: src:
    runCommand "wallpapers-${name}" {nativeBuildInputs = [pkgs.dpkg];} ''
      dpkg-deb -x ${src} x
      mkdir -p $out/share
      cp -r x/usr/share/backgrounds $out/share/backgrounds
    '';
in {
  deepin = pick "deepin" (fetchFromGitHub {
    owner = "linuxdeepin";
    repo = "deepin-wallpapers";
    rev = "a3e73fd1fbbb613c5600d6e8c376b991c8632bc2"; # tag 1.7.28
    hash = "sha256-L1nsBNJJvaffKaXktZ1MHY9N9DE1va2vbXV+W2tbFfU=";
  }) ["deepin" "deepin/platform/deepin" "deepin/platform/uos" "deepin-solidwallpapers"];

  opensuse = pick "opensuse" (fetchFromGitHub {
    owner = "openSUSE";
    repo = "wallpapers";
    rev = "6fac960c9206090946096b3a3154b2de56e4b511";
    hash = "sha256-JJPidDvK/EJWxFa97SH60HPHvTlzII0JybtMnqDxbjs=";
  }) ["leap15" "leap16"];

  solus = pick "solus" (fetchFromGitHub {
    owner = "getsolus";
    repo = "artwork";
    rev = "935b24ac299470d3aea8bddf8f4e3e969a9b1abd";
    hash = "sha256-wL9CdAT26Q4e/OwM/HbHI+f9ke5uLPMUGzxKOgbliZc=";
  }) ["backgrounds"];

  garuda = pick "garuda" (fetchzip {
    url = "https://gitlab.com/garuda-linux/themes-and-settings/artwork/garuda-wallpapers/-/archive/1.1.1/garuda-wallpapers-1.1.1.tar.gz";
    hash = "sha256-HAf9DWperjJlIafVDmoYG5vephAhQLkY5Rv/lkBEGBM=";
  }) ["src/garuda-wallpapers"];

  arch = pick "arch" (fetchzip {
    url = "https://github.com/xyproto/archlinux-wallpaper/releases/download/1.6.1/archlinux-wallpaper-1.6.1.tar.gz";
    hash = "sha256-ztDyFBkLoI7F1VAa7XKEbf5RUmEKnz6zIVvJyzA1zeg=";
  }) ["img"];

  mint = pick "mint" (fetchzip {
    url = "http://packages.linuxmint.com/pool/main/m/mint-backgrounds-wilma/mint-backgrounds-wilma_1.1.tar.gz";
    hash = "sha256-aDn3o0NvrGxLsVQ+7J+GHwj5PeLDLwqP/P3wPCufHhc=";
  }) ["backgrounds/linuxmint-wilma"];

  # desktop-base ships KDE-style themes (wallpaper/contents/images/<resolution>).
  debian = let
    src = fetchzip {
      url = "http://deb.debian.org/debian/pool/main/d/desktop-base/desktop-base_13.0.4.tar.xz";
      hash = "sha256-VbH7DAU+uA8E4BEq6tKguqDn/t2eL7DF88nEoxYABSQ=";
    };
  in
    runCommand "wallpapers-debian" {} ''
      mkdir -p $out/share/wallpapers
      for t in ${src}/*-theme; do
        [ -d "$t/wallpaper/contents" ] || continue
        mkdir -p "$out/share/wallpapers/$(basename "$t")"
        ln -s "$t/wallpaper/contents" "$out/share/wallpapers/$(basename "$t")/contents"
      done
    '';

  ubuntu-stonking = fromDeb "ubuntu-stonking" (fetchurl {
    url = "http://archive.ubuntu.com/ubuntu/pool/main/u/ubuntu-wallpapers/ubuntu-wallpapers-stonking_26.10.1_all.deb";
    hash = "sha256-6pbjF3Nb5Kn26J2tmZWpp0I7Kzcw+Dqm8xqllrQAbMQ=";
  });

  ubuntu-resolute = fromDeb "ubuntu-resolute" (fetchurl {
    url = "http://archive.ubuntu.com/ubuntu/pool/main/u/ubuntu-wallpapers/ubuntu-wallpapers-resolute_26.10.1_all.deb";
    hash = "sha256-zO+fTzqtqiea79BoB2gbrwRaljFi8efFrxt2/Wkk+vM=";
  });

  kali = fromDeb "kali" (fetchurl {
    url = "http://http.kali.org/kali/pool/main/k/kali-wallpapers/kali-wallpapers-2026_2026.3.0_all.deb";
    hash = "sha256-FaNFoERizUkLiccQk9iPR3Yor1OVbS7CuLOM5LhkUMY=";
  });
}

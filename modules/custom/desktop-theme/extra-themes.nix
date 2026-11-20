# kitty-themes（nixpkgs）に無い配色を、mbadolato/iTerm2-Color-Schemes の kitty/ から足す
# （2026-11-20。Iceberg と、色の傾きが近い物）。repo は MIT。1 ファイルずつ rev と hash を固定。
# キー = 一覧に出す名前（空白なし）、値 = { file = kitty/ 下のファイル名; hash = ...; }。
{pkgs}: let
  rev = "1c3e1ef1145b1ba4b867549c8c6852da9a1c8f0b";
  get = file: hash:
    pkgs.fetchurl {
      name = "${builtins.replaceStrings [" "] ["_"] file}.conf";
      url = "https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/${rev}/kitty/${
        builtins.replaceStrings [" "] ["%20"] file
      }.conf";
      inherit hash;
    };
in {
  Iceberg_Dark = get "Iceberg Dark" "sha256-nD9ky6hPPu8KpiIN1K9jh1K79Q8xglT66cU8u3Fszgo=";
  Kanagawabones = get "Kanagawabones" "sha256-u/SxzD2/gxwfeW1ewCpa25MsDu+EvXNPOSiLF4MdsTs=";
  Midnight_Tundra = get "Midnight Tundra" "sha256-7Do6PgZEv7VzNvYVm0P6yiQ5CEGZK0hmvMSaZHB4m+4=";
  Sonoran_Blue_Hour = get "Sonoran Blue Hour" "sha256-Yd+ioSXACb2p1yD8sLs85YPvYRTOaBGcsrdgeWV+Iek=";
  Kanso_Ink = get "Kanso Ink" "sha256-Vkzv5yxu4nUM/acus5qtyym9PUYElPw0aDxrEjezX7M=";
  Everblush = get "Everblush" "sha256-MeKv+yAQBrowT2Mj0sjcS3WqjckO/ymOlk/v7V2aNP0=";
  Onenord = get "Onenord" "sha256-TOA0yTTQyFCYRowKOulobtbC13ofIgqYpJhb0eCJDYU=";
  Oceanic_Next = get "Oceanic Next" "sha256-8kBbpr0yJXcqe0k6KG3rehchqXZRHXa7e/kmMGw+6Ic=";
}

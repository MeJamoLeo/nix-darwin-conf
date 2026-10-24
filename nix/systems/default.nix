# fleet の system 集合（nix-systems 形式＝リストを返す default.nix）。
# mac 3台 = aarch64-darwin、x1nano = x86_64-linux。x86_64-darwin は nixpkgs 26.11 で
# サポートが落ちたので入れない（入れると他 flake の per-system 評価が throw する）。
["aarch64-darwin" "x86_64-linux"]

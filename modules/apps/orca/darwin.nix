{...}: {
  ##########################################################################
  #
  #  Orca — エージェント（Claude Code / Codex 等）を git worktree ごとに並列で
  #  走らせる Electron 製の ADE。stablyai/orca（MIT・onorca.dev）。
  #  nixpkgs に無いので homebrew cask で入れる。
  #
  #  ★ 素の `orca` cask は **plotly の別物**（plotly チャートの画像生成。macOS の
  #    Gatekeeper を通らず 2026-09-01 に disabled）。欲しいのは公式 tap 側なので、
  #    三段形式 `stablyai/orca/orca` で完全修飾して曖昧さを消す。
  #
  #  更新の持ち主は **アプリ自身**。cask が auto_updates true を宣言していて
  #  （electron-updater が /Applications に新しい Orca.app を書く）、この repo は
  #  homebrew.onActivation.upgrade = false なので switch では触らない＝競合しない。
  #  brew 側から動かしたいときだけ `brew upgrade --cask --greedy stablyai/orca/orca`。
  #
  #  cask は Orca 同梱の CLI（Contents/Resources/bin/orca）も PATH に貼る。
  #
  #  機体限定で入れる（hosts/tanegashima.nix・hosts/ogasawara.nix から import）。
  #  profiles/mac-workstation.nix に置かない理由＝dejima は使い捨て VM で、
  #  GUI の ADE を配る意味が無いため。全機に広げたくなったら profile へ移す。
  #
  ##########################################################################

  #  ## 初回導入でコケたときは `brew update` を先に（2026-10-25 の実測）
  #
  #  tap 追加と同じ switch で bundle が cask を入れようとして "Installing orca has failed!"
  #  で落ち、activation 全体が止まった。直後に手で `brew install --cask stablyai/orca/orca`
  #  を叩いたら、brew 本体の self-update が走ったうえで成功した。
  #  **原因は未確定**（brew のエラー本文は bundle に握り潰されて残っていない）。有力なのは
  #  onActivation.autoUpdate = false ＝ HOMEBREW_NO_AUTO_UPDATE で、tap を足した直後の
  #  古い index のまま cask を引こうとしたこと。新機体（ogasawara）で同じ所で落ちたら
  #  `brew update` → 再 switch で抜ける。
  homebrew.taps = ["stablyai/orca"];
  homebrew.casks = ["stablyai/orca/orca"];
}

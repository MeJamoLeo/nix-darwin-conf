{
  config,
  pkgs,
  ...
}: {
  # todo-board — 日次 Todo ファイル（~/Store/30_Work/todo/YYYY/YYYYMMDD-todo.md）の
  # 繰り越しと、fzf での ▶/■ 時間刻み。設計＝vault の todo-board-design。
  #
  # ★ 時刻刻みをエディタから切り離した: nvim を開く→行へ移動→キー、は1タスクごとの操作として
  #   重すぎる（ユーザーの指摘 2026-10-02）。`todo` は fzf でタスクを選ぶだけで ▶/■ が刻まれ、
  #   どの端末でも、`ssh -t ogasawara todo` でも動く。nvim のキーマップは編集中の補助として残す。
  #   コマンド面: `todo`（選んで刻む）／`todo edit`（エディタで開く）／`todo add <text>`（追記）。
  # 実装は ./bin/todo-board（python3 1本・標準ライブラリのみ）。
  #
  # なぜ custom バケツか: 価値の中心が自分のコード（繰り越し規則）で、nvim の配線は付随。
  #
  # ★ 設計の核＝起動役を launchd に置く。台帳・メール digest・mac-study-tracker は
  #   「セッション／人間の手動」頼みで全滅、record-blocks と gcal-dash（launchd）だけ生存した。
  #   だから 06:00 の確定（roll）は人間もセッションも介さず launchd が打つ。

  home.file."bin/todo-board" = {
    source = ./bin/todo-board;
    executable = true;
  };

  # `todo` = `todo-board pick`（引数があれば edit / add をそのまま渡す）。alias ではなく PATH 上のファイルにする:
  #   alias は対話シェルでしか効かず、ssh ogasawara 経由の非対話実行や他シェルで消える。
  #   python は store パス固定（shebang の env python3 に依存しない）。
  home.file."bin/todo" = {
    executable = true;
    text = ''
      #!/bin/sh
      # fzf は store パス固定（ssh／launchd の最小 PATH でも動かすため）。
      export TODO_BOARD_FZF="${pkgs.fzf}/bin/fzf"
      sub=pick
      case "''${1:-}" in
        "") ;;
        edit|add) sub=$1; shift ;;
        -h|--help|help)
          cat <<'USAGE'
      todo - today's todo list (~/Store/30_Work/todo/YYYY/YYYYMMDD-todo.md)

        todo              pick an open task: 1st pick = ▶ start, 2nd pick = ■ finish (duration)
        todo add <text>   append a task to # Inbox
        todo edit         open today's file in $EDITOR
        todo -h           show this help

      Open tasks are copied to the next day at 06:00; the old line is kept as [>] with "→ M/D".
      USAGE
          exit 0 ;;
        *) echo "todo: unknown subcommand '$1' (see todo -h)" >&2; exit 2 ;;
      esac
      exec ${pkgs.python3}/bin/python3 "${config.home.homeDirectory}/bin/todo-board" "$sub" "$@"
    '';
  };

  # 06:00 に当日ファイルを確定し、RunAtLoad で switch／ログイン時にも作る。
  #   ⚠ python は PATH から探さない（launchd の PATH は最小。record-blocks と同じ罠）。
  #   ⚠ roll は冪等（当日ファイルがあれば何もしない）なので RunAtLoad や
  #     起床後の取りこぼし再実行で二重に走っても壊れない。
  #   ⚠ Mac が 06:00 に寝ていても、起床後に launchd が取りこぼし分を1回走らせる。
  launchd.agents.todo-board-roll = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.python3}/bin/python3"
        "${config.home.homeDirectory}/bin/todo-board"
        "roll"
      ];
      StartCalendarInterval = [
        {
          Hour = 6;
          Minute = 0;
        }
      ];
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/todo-board.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/todo-board.err.log";
    };
  };

  # nvim: （`todo` の pick と同じ規則。編集中の補助）<leader>t で今日の Todo 行に ▶開始 → ■終了（所要）を刻む。
  #   ▶ だけあって ■ が無い行＝作業がブレた跡（設計の狙い）。
  #   ★ modules/apps/nixvim/home.nix は触らない。extraConfigLua は lines 型で、
  #     nixvim が複数モジュールの定義を結合するのでここから足せる。
  #   ★ バッファローカル（BufEnter で pattern 限定）にして、他のファイルでは <leader>t を空けておく。
  #   ⚠ 日跨ぎ（▶23:50 → ■00:10）は所要が負になるので 24h 足す。
  programs.nixvim.extraConfigLua = ''
    do
      local function todo_toggle()
        local lnum = vim.api.nvim_win_get_cursor(0)[1]
        local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1] or ""
        if not line:match("^%s*%- %[.%]") then
          vim.notify("todo: not a task line", vim.log.levels.WARN)
          return
        end
        local now = os.date("%H:%M")
        if line:find("■", 1, true) then
          vim.notify("todo: already finished (■)", vim.log.levels.INFO)
        elseif not line:find("▶", 1, true) then
          line = line .. " ▶" .. now
          vim.api.nvim_buf_set_lines(0, lnum - 1, lnum, false, { line })
        else
          local h, m = line:match("▶(%d+):(%d+)")
          local nh, nm = now:match("(%d+):(%d+)")
          local mins = (tonumber(nh) * 60 + tonumber(nm)) - (tonumber(h) * 60 + tonumber(m))
          if mins < 0 then mins = mins + 24 * 60 end
          line = line .. " ■" .. now .. " (" .. mins .. "m)"
          line = line:gsub("^(%s*%- )%[ %]", "%1[x]", 1)
          vim.api.nvim_buf_set_lines(0, lnum - 1, lnum, false, { line })
        end
      end
      vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
        pattern = "*/todo/*/*-todo.md",
        callback = function(ev)
          vim.keymap.set("n", "<leader>t", todo_toggle, { buffer = ev.buf, desc = "todo: ▶/■ time stamp" })
        end,
      })
    end
  '';
}

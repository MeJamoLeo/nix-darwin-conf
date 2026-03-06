{
  pkgs,
  username,
  ...
}: {
  # texlive + Skim
  homebrew = {
    brews = [
      "texlive" # LaTeX distribution
    ];
    casks = [
      "skim" # PDF viewer with SyncTeX support
    ];
  };

  # Neovim LaTeX 設定（home-manager 経由）
  home-manager.users.${username} = {
    home.packages = with pkgs; [
      neovim-remote # Skim からの逆検索用 (nvr)
    ];

    programs.nixvim = {
      autoCmd = [
        {
          event = "BufNewFile";
          pattern = "*.tex";
          desc = "Insert minimal LaTeX template for new .tex files";
          callback.__raw = ''
            function()
              local lines = {
                "\\documentclass{article}",
                "",
                "\\begin{document}",
                "",
                "",
                "\\end{document}",
              }
              vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
              vim.api.nvim_win_set_cursor(0, {5, 0})
            end
          '';
        }
      ];

      globals.tex_flavor = "latex";

      keymaps = [
        # LaTeX: コンパイル開始/停止
        {
          action = "<CMD>VimtexCompile<CR>";
          key = "<leader>ltc";
          mode = "n";
          options.desc = "[L]a[T]eX [C]ompile";
        }
        # LaTeX: PDF を Skim で表示
        {
          action = "<CMD>VimtexView<CR>";
          key = "<leader>ltv";
          mode = "n";
          options.desc = "[L]a[T]eX [V]iew";
        }
        # LaTeX: プレビュー（コンパイル＋Skim表示）
        {
          action = "<CMD>VimtexView<CR>";
          key = "<leader>p";
          mode = "n";
          options.desc = "[P]review LaTeX";
        }
        # LaTeX: エラー一覧
        {
          action = "<CMD>VimtexErrors<CR>";
          key = "<leader>lte";
          mode = "n";
          options.desc = "[L]a[T]eX [E]rrors";
        }
        # LaTeX: 補助ファイル削除
        {
          action = "<CMD>VimtexClean<CR>";
          key = "<leader>ltx";
          mode = "n";
          options.desc = "[L]a[T]eX Clean (x)";
        }
        # LaTeX: コンパイル停止
        {
          action = "<CMD>VimtexStop<CR>";
          key = "<leader>ltk";
          mode = "n";
          options.desc = "[L]a[T]eX [K]ill";
        }
        # LaTeX: 目次パネル表示切替
        {
          action = "<CMD>VimtexTocToggle<CR>";
          key = "<leader>ltt";
          mode = "n";
          options.desc = "[L]a[T]eX [T]OC";
        }
      ];

      plugins = {
        vimtex = {
          enable = true;
          settings = {
            view_method = "skim";
            view_skim_sync = 1;
            view_skim_activate = 1;
            view_automatic = 0;
          };
        };

        lsp.servers.texlab.enable = true;

        treesitter.grammarPackages = [
          pkgs.vimPlugins.nvim-treesitter.builtGrammars.latex
        ];
      };
    };
  };
}

# LaTeX 用 Neovim 設定 (vimtex + texlab + 雛形挿入 + sioyek 連携)。
# texlive は同ディレクトリの darwin.nix。sioyek 本体は modules/apps/sioyek
# （PDF 既定ビューアとして mac・x1nano 共通）。
{pkgs, ...}: {
  home.packages = with pkgs; [
    pandoc # Markdown → PDF。エンジンは texlive の xelatex（darwin.nix 側）
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
      # LaTeX: PDF を sioyek で表示
      {
        action = "<CMD>VimtexView<CR>";
        key = "<leader>ltv";
        mode = "n";
        options.desc = "[L]a[T]eX [V]iew";
      }
      # LaTeX: プレビュー（コンパイル＋sioyek表示）
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
          # sioyek（2026-10-23 に Skim から移行）。順方向 SyncTeX は vimtex が --forward-search で、
          # 逆方向（PDF をクリック → ソース行）は vimtex が sioyek に --inverse-search を渡して
          # `nvim --headless -c VimtexInverseSearch` で戻ってくる（nvr は不要）。
          view_method = "sioyek";
          view_automatic = 0;
        };
      };

      lsp.servers.texlab.enable = true;

      treesitter.grammarPackages = [
        pkgs.vimPlugins.nvim-treesitter.builtGrammars.latex
      ];
    };
  };
}

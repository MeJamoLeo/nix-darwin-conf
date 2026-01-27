# nixvim.nix - Neovim configuration via nixvim
# LSP、補完、ファジーファインダー、Git連携などを設定
{pkgs, ...}: let
  # カーソル位置の診断メッセージをフロートウィンドウで自動表示
  diagnosticFloatAutocmd = ''
    vim.api.nvim_create_autocmd("CursorHold", {
      callback = function()
        vim.diagnostic.open_float(nil, { focusable = false, scope = "cursor" })
      end,
    })
  '';

  # nvim-autopairs の設定
  # Lisp系言語ではシングルクォートのペアリングを無効化（クォート構文のため）
  nvimAutopairsConfig = ''
    local npairs = require("nvim-autopairs")
    local Rule = require("nvim-autopairs.rule")

    npairs.remove_rule("'")
    npairs.add_rules({
      Rule("'", "'")
        :with_pair(function(opts)
          local disabled = { "lisp", "commonlisp", "scheme", "clojure", "fennel" }
          return not vim.tbl_contains(disabled, opts.filetype)
        end),
    })
  '';

  # rainbow-delimiters の設定
  # 括弧を虹色でハイライトし、対応を視覚的に分かりやすくする
  # Kanagawa テーマに合わせたカラーパレット
  rainbowDelimitersConfig = ''
    local rd = require("rainbow-delimiters")

    vim.g.rainbow_delimiters = {
      strategy = {
        [""] = rd.strategy["global"],
        commonlisp = rd.strategy["local"],
      },
      highlight = {
        "RainbowDelimiterRed",
        "RainbowDelimiterOrange",
        "RainbowDelimiterYellow",
        "RainbowDelimiterGreen",
        "RainbowDelimiterCyan",
        "RainbowDelimiterBlue",
        "RainbowDelimiterViolet",
      },
    }

    local palette = {
      RainbowDelimiterRed = "#c34043",
      RainbowDelimiterOrange = "#ffa066",
      RainbowDelimiterYellow = "#c0a36e",
      RainbowDelimiterGreen = "#76946a",
      RainbowDelimiterCyan = "#6a9589",
      RainbowDelimiterBlue = "#7e9cd8",
      RainbowDelimiterViolet = "#957fb8",
    }

    for group, color in pairs(palette) do
      vim.api.nvim_set_hl(0, group, { fg = color, bold = true })
    end
  '';

  # 不可視文字の表示設定
  listchars = {
    eol = "↲"; # 行末
    extends = "»"; # 右にはみ出し
    nbsp = "%"; # ノーブレークスペース
    precedes = "«"; # 左にはみ出し
    tab = "»-"; # タブ
    trail = "-"; # 行末空白
  };

  # nvim-cmp のキーマッピング
  cmpMappings = {
    "<C-Space>" = "cmp.mapping.complete()"; # 補完メニュー表示
    "<C-d>" = "cmp.mapping.scroll_docs(-4)"; # ドキュメント上スクロール
    "<C-e>" = "cmp.mapping.close()"; # 補完キャンセル
    "<C-f>" = "cmp.mapping.scroll_docs(4)"; # ドキュメント下スクロール
    "<C-j>" = "cmp.mapping.select_next_item()"; # 次の候補
    "<C-k>" = "cmp.mapping.select_prev_item()"; # 前の候補
    "<C-n>" = "cmp.mapping.select_next_item()"; # 次の候補（vim標準）
    "<C-p>" = "cmp.mapping.select_prev_item()"; # 前の候補（vim標準）
    "<CR>" = "cmp.mapping.confirm({ behavior = cmp.ConfirmBehavior.Insert, select = true })";
    "<Down>" = "cmp.mapping.select_next_item()";
    "<Up>" = "cmp.mapping.select_prev_item()";
  };

  # 補完ソース（優先度順）
  cmpSources = [
    {name = "buffer";} # バッファ内の単語
    {name = "nvim_lsp";} # LSP
    {name = "path";} # ファイルパス
  ];

  # LSP サーバー設定
  lspServers = {
    bashls.enable = true; # Bash
    clangd.enable = true; # C/C++
    dockerls.enable = true; # Dockerfile
    lua_ls = {
      enable = true;
      settings.telemetry.enable = false;
    };
    marksman.enable = true; # Markdown
    nixd.enable = true; # Nix
    pyright.enable = true; # Python
  };

  # カスタムキーマップ
  nixvimKeymaps = [
    # jj でインサートモードから抜ける
    {
      action = "<esc>";
      key = "jj";
      mode = "i";
    }
    # Esc 2回で検索ハイライト解除
    {
      action = ":set nohlsearch<CR>";
      key = "<esc><esc>";
      mode = "n";
    }
    # LazyGit 起動
    {
      action = "<CMD>LazyGit<CR>";
      key = "<leader>lg";
      mode = "n";
      options.desc = "[L]azy[G]it";
    }
    # smart-splits: ウィンドウリサイズモード
    {
      action = "<CMD>SmartResizeMode<CR>";
      key = "<C-e> ";
      mode = "n";
      options.desc = "Resize Mode";
    }
    # smart-splits: ウィンドウ入れ替え
    {
      action = "<CMD>SmartSwapLeft<CR>";
      key = "<C-e>h";
      mode = "n";
      options.desc = "Swap Left";
    }
    {
      action = "<CMD>SmartSwapDown<CR>";
      key = "<C-e>j";
      mode = "n";
      options.desc = "Swap Down";
    }
    {
      action = "<CMD>SmartSwapUp<CR>";
      key = "<C-e>k";
      mode = "n";
      options.desc = "Swap Up";
    }
    {
      action = "<CMD>SmartSwapRight<CR>";
      key = "<C-e>l";
      mode = "n";
      options.desc = "Swap Right";
    }
    # Telescope ファイルブラウザ
    {
      action = "<CMD>Telescope file_browser<CR>";
      key = "<leader>e";
      mode = "n";
      options.desc = "File Browser";
    }
  ];

  # Telescope キーマップ
  telescopeKeymaps = {
    "<leader>fb" = {
      action = "buffers";
      mode = "n";
      options.desc = "[F]ind [B]uffers";
    };
    "<leader>fc" = {
      action = "colorscheme";
      mode = "n";
      options.desc = "[F]ind [C]olorscheme";
    };
    "<leader>ff" = {
      action = "find_files";
      mode = "n";
      options.desc = "[F]ind [F]iles";
    };
    "<leader>fg" = {
      action = "git_files";
      mode = "n";
      options.desc = "[F]ind [G]it files";
    };
    "<leader>fw" = {
      action = "grep_string";
      mode = "n";
      options.desc = "[F]ind current [W]ord";
    };
  };

  # Treesitter 対応言語
  treesitterGrammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
    bash
    commonlisp
    cpp
    json
    lua
    make
    markdown
    nix
    regex
    toml
    vim
    vimdoc
    xml
    yaml
  ];
in {
  programs.nixvim = {
    # クリップボード連携（macOS pbcopy）
    clipboard.providers.pbcopy.enable = true;

    # カラースキーム: Kanagawa（ダークテーマ）
    colorschemes.kanagawa = {
      autoLoad = true;
      enable = true;
    };

    defaultEditor = true;
    enable = true;

    # Lua 設定の挿入
    extraConfigLua = diagnosticFloatAutocmd + nvimAutopairsConfig;
    extraConfigLuaPre = rainbowDelimitersConfig;

    # グローバル変数
    globals = {
      mapleader = " "; # リーダーキーをスペースに
      # ターミナルのカラーを無視
      t_Co = "";
      t_ut = "";
    };

    keymaps = nixvimKeymaps;

    # エディタオプション
    opts = {
      autoindent = true;
      background = "dark";
      clipboard = "unnamedplus"; # システムクリップボード連携
      expandtab = false; # タブをスペースに展開しない
      list = true; # 不可視文字表示
      listchars = listchars;
      number = true; # 行番号表示
      relativenumber = true; # 相対行番号
      shiftwidth = 4;
      showtabline = 2; # 常にタブライン表示
      signcolumn = "yes"; # サイン列を常に表示
      softtabstop = 0;
      tabstop = 4;
      termguicolors = true; # 24bit カラー
    };

    # プラグイン設定
    plugins = {
      # 補完エンジン
      cmp = {
        enable = true;
        settings = {
          mapping = cmpMappings;
          sources = cmpSources;
        };
      };
      cmp-buffer.enable = true; # バッファ補完
      cmp-nvim-lsp.enable = true; # LSP 補完
      cmp-path.enable = true; # パス補完

      # Git 差分表示
      gitgutter = {
        enable = true;
        settings = {
          highlight_linenrs = true;
          highlight_lines = true;
        };
      };

      # Git クライアント
      lazygit.enable = true;

      # LSP
      lsp = {
        enable = true;
        servers = lspServers;
      };

      # 括弧の自動補完
      nvim-autopairs.enable = true;

      # 括弧の虹色ハイライト
      rainbow-delimiters.enable = true;

      # ウィンドウ分割・リサイズ
      smart-splits.enable = true;

      # ファジーファインダー
      telescope = {
        enable = true;
        extensions = {
          file-browser.enable = true; # ファイルブラウザ
          fzf-native.enable = true; # 高速検索
          ui-select.enable = true; # UI選択
        };
        keymaps = telescopeKeymaps;
        settings = {
          pickers = {
            find_files = {
              hidden = true; # 隠しファイルを含める
            };
            grep_string = {
              additional_args = ["--hidden"]; # 隠しファイルを含める
            };
            live_grep = {
              additional_args = ["--hidden"]; # 隠しファイルを含める
            };
          };
        };
      };

      # シンタックスハイライト
      treesitter = {
        enable = true;
        grammarPackages = treesitterGrammars;
      };

      # 対応括弧ジャンプ強化
      vim-matchup = {
        enable = true;
        settings = {
          enabled = 1;
          matchparen_deferred = 1;
          matchparen_enabled = 1;
        };
        treesitter.enable = true;
      };

      # ファイルアイコン
      web-devicons.enable = true;

      # キーバインドヘルプ表示
      which-key.enable = true;
    };

    # コマンドエイリアス
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
  };
}

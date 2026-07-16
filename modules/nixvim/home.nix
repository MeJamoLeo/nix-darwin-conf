# nixvim.nix - Neovim configuration via nixvim
# LSP、補完、ファジーファインダー、Git連携などを設定
{pkgs, config, ...}: let
  # CP デバッグ用: debugpy 入り python と、sample-N.in を stdin にして対象ファイルを
  # debugpy 下で実行するランナー（x1nano nixos-cp から移植）。
  pythonWithDebugpy = pkgs.python3.withPackages (ps: [ps.debugpy]);
  cpDebugRunner = pkgs.writeText "cp-debug-runner.py" ''
    import os, sys, runpy
    script, input_file = sys.argv[1], sys.argv[2]
    sys.stdin = open(input_file, "r")
    os.chdir(os.path.dirname(os.path.abspath(script)))
    sys.argv = [script]
    runpy.run_path(script, run_name="__main__")
  '';

  # CP 用 Lua（luasnip ローダー＋markdown 数式スニペット＋DAP の CP デバッグ config
  # ビルダー）。x1nano nixos-cp modules/nvim/default.nix から逐語移植。
  cpNvimLua = ''
    local ls = require("luasnip")
    local s = ls.snippet
    local t = ls.text_node
    local i = ls.insert_node

    -- ~/cp/snippets/<filetype>.lua を読む（この repo への out-of-store symlink 経由）
    require("luasnip.loaders.from_lua").lazy_load({
      paths = vim.fn.expand("~/cp/snippets"),
    })

    ls.add_snippets("markdown", {
      s("$", { t("$"), i(1), t("$") }),
      s("$$", { t("$$"), i(1), t("$$") }),
      s("On", { t("$O(n)$") }),
      s("Onlogn", { t("$O(n \\log n)$") }),
      s("On2", { t("$O(n^2)$") }),
      s("Ologn", { t("$O(\\log n)$") }),
      s("sum", { t("$\\sum_{"), i(1, "i=1"), t("}^{"), i(2, "n"), t("} "), i(3), t("$") }),
      s("frac", { t("$\\frac{"), i(1), t("}{"), i(2), t("}$") }),
      s("sqrt", { t("$\\sqrt{"), i(1), t("}$") }),
      s("leq", { t("$\\leq$") }),
      s("geq", { t("$\\geq$") }),
      s("neq", { t("$\\neq$") }),
      s("inf", { t("$\\infty$") }),
      s("floor", { t("$\\lfloor "), i(1), t(" \\rfloor$") }),
      s("ceil", { t("$\\lceil "), i(1), t(" \\rceil$") }),
      s("mod", { t("$"), i(1), t(" \\bmod "), i(2), t("$") }),
      s("arr", { t("$a_"), i(1, "i"), t("$") }),
      s("dp", { t("$dp["), i(1), t("]"), t("$") }),
    })

    -- CP debug: 現在ファイルを debugpy 下で test/sample-N.in を stdin に実行する DAP config
    _G.cp_debug_config = function()
      local file = vim.fn.expand("%:p")
      local dir = vim.fn.expand("%:p:h")
      local tc = vim.fn.input("Testcase number: ", "1")
      if tc == "" then tc = "1" end
      local input_file = dir .. "/test/sample-" .. tc .. ".in"
      if vim.fn.filereadable(input_file) == 0 then
        vim.notify("Input file not found: " .. input_file, vim.log.levels.ERROR)
        return nil
      end
      return {
        type = "python",
        request = "launch",
        name = "CP: " .. vim.fn.fnamemodify(file, ":t") .. " < sample-" .. tc .. ".in",
        program = "${cpDebugRunner}",
        args = { file, input_file },
        cwd = dir,
        console = "integratedTerminal",
        justMyCode = false,
      }
    end
  '';

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

    local lisp_filetypes = { "lisp", "commonlisp", "scheme", "clojure", "fennel" }

    local sq = string.char(39) -- single quote
    npairs.remove_rule(sq)
    npairs.remove_rule("`")
    npairs.remove_rule('"')
    npairs.add_rules({
      Rule(sq, sq)
        :with_pair(function()
          return not vim.tbl_contains(lisp_filetypes, vim.bo.filetype)
        end),
      Rule("`", "`")
        :with_pair(function()
          return not vim.tbl_contains(lisp_filetypes, vim.bo.filetype)
        end),
      Rule('"', '"')
        :with_pair(function()
          return not vim.tbl_contains(lisp_filetypes, vim.bo.filetype)
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
        commonlisp = rd.strategy["global"],
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
    # Tab でスニペット展開/ジャンプ（luasnip）。展開対象が無ければ通常の Tab。
    "<Tab>" = ''cmp.mapping(function(fallback)
      local luasnip = require("luasnip")
      if luasnip.expand_or_jumpable() then luasnip.expand_or_jump() else fallback() end
    end, {"i", "s"})'';
    "<S-Tab>" = ''cmp.mapping(function(fallback)
      local luasnip = require("luasnip")
      if luasnip.jumpable(-1) then luasnip.jump(-1) else fallback() end
    end, {"i", "s"})'';
  };

  # 補完ソース（優先度順）
  cmpSources = [
    {name = "luasnip";} # スニペット（CP snippets）
    {name = "buffer";} # バッファ内の単語
    {name = "nvim_lsp";} # LSP
    {name = "omni";} # オムニ補完（Vlime等）
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
    # CP: competitest（x1nano modules/nvim/default.nix から忠実移植）。
    # competitest は自前ランナーで oj ラッパーを通らないため、STOPWATCH の
    # 臨戦マーカーは <leader>cs（cp-submit）が発火する（提出こそ最強の予兆）。
    {
      action = "<cmd>CompetiTest run<cr>";
      key = "<leader>cr";
      mode = "n";
      options.desc = "Run testcases";
    }
    {
      action = "<cmd>w<cr><cmd>!cp-submit %<cr>";
      key = "<leader>cs";
      mode = "n";
      options.desc = "Save + submit";
    }
    {
      action = "<cmd>CompetiTest add_testcase<cr>";
      key = "<leader>ca";
      mode = "n";
      options.desc = "Add testcase";
    }
    {
      action = "<cmd>CompetiTest edit_testcase<cr>";
      key = "<leader>ce";
      mode = "n";
      options.desc = "Edit testcase";
    }
    {
      action = "<cmd>CompetiTest receive testcases<cr>";
      key = "<leader>ct";
      mode = "n";
      options.desc = "Receive testcases";
    }
    # smart-splits: ウィンドウリサイズ (Ctrl+q)
    {
      action.__raw = "function() require('smart-splits').resize_left() end";
      key = "<C-q>h";
      mode = "n";
      options.desc = "Resize Left";
    }
    {
      action.__raw = "function() require('smart-splits').resize_down() end";
      key = "<C-q>j";
      mode = "n";
      options.desc = "Resize Down";
    }
    {
      action.__raw = "function() require('smart-splits').resize_up() end";
      key = "<C-q>k";
      mode = "n";
      options.desc = "Resize Up";
    }
    {
      action.__raw = "function() require('smart-splits').resize_right() end";
      key = "<C-q>l";
      mode = "n";
      options.desc = "Resize Right";
    }
    # smart-splits: ウィンドウ入れ替え (Ctrl+e)
    {
      action.__raw = "function() require('smart-splits').swap_buf_left() end";
      key = "<C-e>h";
      mode = "n";
      options.desc = "Swap Left";
    }
    {
      action.__raw = "function() require('smart-splits').swap_buf_down() end";
      key = "<C-e>j";
      mode = "n";
      options.desc = "Swap Down";
    }
    {
      action.__raw = "function() require('smart-splits').swap_buf_up() end";
      key = "<C-e>k";
      mode = "n";
      options.desc = "Swap Up";
    }
    {
      action.__raw = "function() require('smart-splits').swap_buf_right() end";
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
    # DAP（デバッガ・全 leader ベース。x1nano から移植）
    {action = "<cmd>DapContinue<cr>";        key = "<leader>dc"; mode = "n"; options.desc = "Debug: Continue/start";}
    {action = "<cmd>DapStepOver<cr>";        key = "<leader>do"; mode = "n"; options.desc = "Debug: Step over";}
    {action = "<cmd>DapStepInto<cr>";        key = "<leader>di"; mode = "n"; options.desc = "Debug: Step into";}
    {action = "<cmd>DapStepOut<cr>";         key = "<leader>dO"; mode = "n"; options.desc = "Debug: Step out";}
    {action = "<cmd>DapToggleBreakpoint<cr>"; key = "<leader>db"; mode = "n"; options.desc = "Debug: Breakpoint";}
    {action = "<cmd>lua require('dap').set_breakpoint(vim.fn.input('Condition: '))<cr>"; key = "<leader>dB"; mode = "n"; options.desc = "Debug: Conditional breakpoint";}
    {action = "<cmd>DapToggleRepl<cr>";      key = "<leader>dr"; mode = "n"; options.desc = "Debug: Toggle REPL";}
    {action = "<cmd>DapTerminate<cr>";       key = "<leader>dx"; mode = "n"; options.desc = "Debug: Terminate";}
    {action = "<cmd>lua require('dapui').toggle()<cr>"; key = "<leader>du"; mode = "n"; options.desc = "Debug: Toggle UI";}
    {action = "<cmd>lua require('dap-python').test_method()<cr>"; key = "<leader>dt"; mode = "n"; options.desc = "Debug nearest test (Python)";}
    {action = "<cmd>lua require('dap-python').debug_selection()<cr>"; key = "<leader>dn"; mode = "v"; options.desc = "Debug selection (Python)";}
    {action = "<cmd>lua require('dap').run(_G.cp_debug_config())<cr>"; key = "<leader>cd"; mode = "n"; options.desc = "CP debug (stdin = test/sample-N.in)";}
    # Nabla（LaTeX 数式レンダリング）
    {action = "<cmd>lua require('nabla').popup()<cr>"; key = "<leader>np"; mode = "n"; options.desc = "Nabla: popup math under cursor";}
    {action = "<cmd>lua require('nabla').toggle_virt({autogen=true})<cr>"; key = "<leader>nt"; mode = "n"; options.desc = "Nabla: toggle inline math";}
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
    c
    commonlisp
    cpp
    go
    json
    lua
    make
    markdown
    nix
    python
    regex
    rust
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
      settings.transparent = true; # 背景透過
    };

    defaultEditor = true;
    enable = true;

    # 追加プラグイン（nixvim に専用オプションがないもの）
    extraPlugins = with pkgs.vimPlugins; [
      vim-table-mode # Markdown テーブル自動整形
      nabla-nvim # LaTeX 数式をバッファ内にレンダリング（<leader>np/nt）
    ];

    # Lua 設定の挿入（CP スニペットローダー・数式スニペット・DAP デバッグ config 込み）
    extraConfigLua = diagnosticFloatAutocmd + nvimAutopairsConfig + cpNvimLua;
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
      expandtab = true; # インデントはスペース（x1nano/CP 環境と統一。Python が主体で安全）
      list = true; # 不可視文字表示
      listchars = listchars;
      number = true; # 行番号表示
      relativenumber = false; # 絶対行番号
      shiftwidth = 4;
      showtabline = 2; # 常にタブライン表示
      signcolumn = "yes"; # サイン列を常に表示
      softtabstop = 4; # Tab/Backspace が 4 スペースを 1 単位として扱う
      tabstop = 4;
      termguicolors = true; # 24bit カラー
    };

    # プラグイン設定
    plugins = {
      # CP: compile + run + test in nvim（x1nano から忠実移植・oj の test/ 形式に適合）
      competitest = {
        enable = true;
        settings = {
          save_current_file = true;
          compile_command = {
            cpp = {
              exec = "g++";
              args = ["-std=c++20" "-O2" "-Wall" "$(FNAME)" "-o" "$(FNOEXT)"];
            };
          };
          run_command = {
            cpp.exec = "./$(FNOEXT)";
            python = {
              exec = "python3";
              args = ["$(FNAME)"];
            };
          };
          runner_ui.interface = "popup";
          output_compare_method = "squish";
          maximum_time = 5000;
          # oj downloadのtest/ディレクトリに合わせる
          testcases_directory = "test";
          testcases_input_file_format = "sample-$(TCNUM).in";
          testcases_output_file_format = "sample-$(TCNUM).out";
        };
      };

      # 補完エンジン
      cmp = {
        enable = true;
        settings = {
          mapping = cmpMappings;
          sources = cmpSources;
          snippet.expand = ''function(args) require("luasnip").lsp_expand(args.body) end'';
        };
      };
      cmp-buffer.enable = true; # バッファ補完
      cmp-nvim-lsp.enable = true; # LSP 補完
      cmp-omni.enable = true; # オムニ補完（Vlime等）
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

      # LSP（ナビゲーションキーマップ込み。x1nano から移植。code_action は competitest
      # <leader>ca と衝突するため x1nano 同様 <leader>la）
      lsp = {
        enable = true;
        servers = lspServers;
        keymaps = {
          lspBuf = {
            "gd" = "definition";
            "gD" = "declaration";
            "gr" = "references";
            "K" = "hover";
            "<leader>rn" = "rename";
            "<leader>la" = "code_action";
          };
          diagnostic = {
            "[d" = "goto_prev";
            "]d" = "goto_next";
          };
        };
      };

      # スニペットエンジン（CP snippets の基盤）
      luasnip.enable = true;

      # DAP（デバッガ）: CP 用に sample-N.in を stdin にステップ実行（<leader>cd）
      dap.enable = true;
      dap-ui.enable = true;
      dap-python = {
        enable = true;
        settings.adapterPythonPath = "${pythonWithDebugpy}/bin/python";
      };
      dap-virtual-text.enable = true;

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
        settings.highlight.additional_vim_regex_highlighting = true;
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

  # CP スニペット: ~/cp/snippets を repo の modules/cp/snippets への out-of-store symlink に。
  # repo の python.lua を編集 → nvim 再起動で即反映（再ビルド不要。x1nano の方式を踏襲）。
  home.file."cp/snippets".source =
    config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/Box/nix-darwin-conf/modules/cp/snippets";
}

{pkgs, ...}: {
  programs.nixvim = {
    defaultEditor = true;
    enable = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    globals = {
      mapleader = " ";
      # ターミナルのカラーを無視
      t_Co = "";
      t_ut = "";
    };
    keymaps = [
      {
        mode = "i";
        key = "jj";
        action = "<esc>";
      }
      {
        mode = "n";
        key = "<esc><esc>";
        action = ":set nohlsearch<CR>";
      }
      {
        mode = "n";
        key = "<leader>lg";
        action = "<CMD>LazyGit<CR>";
        options.desc = "[L]azy[G]it";
      }
      {
        mode = "n";
        key = "<C-e> ";
        action = "<CMD>SmartResizeMode<CR>";
        options.desc = "Resize Mode";
      }
      {
        mode = "n";
        key = "<C-e>h";
        action = "<CMD>SmartSwapLeft<CR>";
        options.desc = "Swap Left";
      }
      {
        mode = "n";
        key = "<C-e>j";
        action = "<CMD>SmartSwapDown<CR>";
        options.desc = "Swap Down";
      }
      {
        mode = "n";
        key = "<C-e>k";
        action = "<CMD>SmartSwapUp<CR>";
        options.desc = "Swap Up";
      }
      {
        mode = "n";
        key = "<C-e>l";
        action = "<CMD>SmartSwapRight<CR>";
        options.desc = "Swap Right";
      }
      {
        mode = "n";
        key = "<leader>e";
        action = "<CMD>Telescope file_browser<CR>";
        options.desc = "File Browser";
      }
    ];
    opts = {
      number = true;
      relativenumber = true;
      clipboard = "unnamedplus";
      expandtab = false;
      tabstop = 4;
      shiftwidth = 4;
      softtabstop = 0;
      showtabline = 2;
      autoindent = true;
      termguicolors = true;
      background = "dark";
      list = true;
      listchars = {
        tab = "»-";
        trail = "-";
        eol = "↲";
        extends = "»";
        precedes = "«";
        nbsp = "%";
      };
      signcolumn = "yes";
    };
    clipboard = {
      providers = {
        pbcopy.enable = true;
      };
    };
    extraConfigLua = ''
      vim.api.nvim_create_autocmd("CursorHold", {
        callback = function()
          vim.diagnostic.open_float(nil, { focusable = false, scope = "cursor" })
        end,
      })
    '';
    plugins = {
      treesitter = {
        enable = true;
        grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
          bash
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
          commonlisp
        ];
      };
      lsp = {
        enable = true;
        servers = {
          clangd = {
            enable = true;
          };
          nixd.enable = true;
          lua_ls = {
            enable = true;
            settings.telemetry.enable = false;
          };
          bashls.enable = true;
          pyright.enable = true;
          marksman.enable = true;
          dockerls.enable = true;
        };
      };
      cmp-buffer.enable = true;
      cmp-nvim-lsp.enable = true;
      cmp-path.enable = true;
      cmp = {
        enable = true;
        settings = {
          sources = [
            {name = "buffer";}
            {name = "nvim_lsp";}
            {name = "path";}
          ];
          mapping = {
            "<C-n>" = "cmp.mapping.select_next_item()";
            "<C-p>" = "cmp.mapping.select_prev_item()";
            "<Down>" = "cmp.mapping.select_next_item()";
            "<Up>" = "cmp.mapping.select_prev_item()";
            "<C-j>" = "cmp.mapping.select_next_item()";
            "<C-k>" = "cmp.mapping.select_prev_item()";
            "<C-d>" = "cmp.mapping.scroll_docs(-4)";
            "<C-f>" = "cmp.mapping.scroll_docs(4)";
            "<C-Space>" = "cmp.mapping.complete()";
            "<C-e>" = "cmp.mapping.close()";
            "<CR>" = "cmp.mapping.confirm({ behavior = cmp.ConfirmBehavior.Insert, select = true })";
          };
        };
      };
      nvim-autopairs.enable = true;
      lazygit.enable = true;
      rainbow-delimiters.enable = true;
      which-key.enable = true;
      smart-splits.enable = true;
      gitgutter = {
        enable = true;
        settings = {
          highlight_linenrs = true;
          highlight_lines = true;
        };
      };
      web-devicons = {
        enable = true;
      };
      telescope = {
        enable = true;
        extensions = {
          fzf-native.enable = true;
          ui-select.enable = true;
          file-browser.enable = true;
        };
        keymaps = {
          "<leader>ff" = {
            mode = "n";
            action = "find_files";
            options = {
              desc = "[F]ind [F]iles";
            };
          };
          "<leader>fg" = {
            mode = "n";
            action = "git_files";
            options = {
              desc = "[F]ind [G]it files";
            };
          };
          "<leader>fw" = {
            mode = "n";
            action = "grep_string";
            options = {
              desc = "[F]ind current [W]ord";
            };
          };
          "<leader>fb" = {
            mode = "n";
            action = "buffers";
            options = {
              desc = "[F]ind [B]uffers";
            };
          };
          "<leader>fc" = {
            mode = "n";
            action = "colorscheme";
            options = {
              desc = "[F]ind [C]olorscheme";
            };
          };
        };
      };
    };
    colorschemes.gruvbox = {
      enable = true;
      autoLoad = true;
    };
  };
}

{pkgs, ...}: let
  diagnosticFloatAutocmd = ''
    vim.api.nvim_create_autocmd("CursorHold", {
      callback = function()
        vim.diagnostic.open_float(nil, { focusable = false, scope = "cursor" })
      end,
    })
  '';

  listchars = {
    eol = "↲";
    extends = "»";
    nbsp = "%";
    precedes = "«";
    tab = "»-";
    trail = "-";
  };

  cmpMappings = {
    "<C-Space>" = "cmp.mapping.complete()";
    "<C-d>" = "cmp.mapping.scroll_docs(-4)";
    "<C-e>" = "cmp.mapping.close()";
    "<C-f>" = "cmp.mapping.scroll_docs(4)";
    "<C-j>" = "cmp.mapping.select_next_item()";
    "<C-k>" = "cmp.mapping.select_prev_item()";
    "<C-n>" = "cmp.mapping.select_next_item()";
    "<C-p>" = "cmp.mapping.select_prev_item()";
    "<CR>" = "cmp.mapping.confirm({ behavior = cmp.ConfirmBehavior.Insert, select = true })";
    "<Down>" = "cmp.mapping.select_next_item()";
    "<Up>" = "cmp.mapping.select_prev_item()";
  };

  cmpSources = [
    {name = "buffer";}
    {name = "nvim_lsp";}
    {name = "path";}
  ];

  lspServers = {
    bashls.enable = true;
    clangd.enable = true;
    dockerls.enable = true;
    lua_ls = {
      enable = true;
      settings.telemetry.enable = false;
    };
    marksman.enable = true;
    nixd.enable = true;
    pyright.enable = true;
  };

  nixvimKeymaps = [
    {
      action = "<esc>";
      key = "jj";
      mode = "i";
    }
    {
      action = ":set nohlsearch<CR>";
      key = "<esc><esc>";
      mode = "n";
    }
    {
      action = "<CMD>LazyGit<CR>";
      key = "<leader>lg";
      mode = "n";
      options.desc = "[L]azy[G]it";
    }
    {
      action = "<CMD>SmartResizeMode<CR>";
      key = "<C-e> ";
      mode = "n";
      options.desc = "Resize Mode";
    }
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
    {
      action = "<CMD>Telescope file_browser<CR>";
      key = "<leader>e";
      mode = "n";
      options.desc = "File Browser";
    }
  ];

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
    clipboard.providers.pbcopy.enable = true;
    colorschemes.gruvbox = {
      autoLoad = true;
      enable = true;
    };
    defaultEditor = true;
    enable = true;
    extraConfigLua = diagnosticFloatAutocmd;
    globals = {
      mapleader = " ";
      # ターミナルのカラーを無視
      t_Co = "";
      t_ut = "";
    };
    keymaps = nixvimKeymaps;
    opts = {
      autoindent = true;
      background = "dark";
      clipboard = "unnamedplus";
      expandtab = false;
      list = true;
      listchars = listchars;
      number = true;
      relativenumber = true;
      shiftwidth = 4;
      showtabline = 2;
      signcolumn = "yes";
      softtabstop = 0;
      tabstop = 4;
      termguicolors = true;
    };
    plugins = {
      cmp = {
        enable = true;
        settings = {
          mapping = cmpMappings;
          sources = cmpSources;
        };
      };
      cmp-buffer.enable = true;
      cmp-nvim-lsp.enable = true;
      cmp-path.enable = true;
      gitgutter = {
        enable = true;
        settings = {
          highlight_linenrs = true;
          highlight_lines = true;
        };
      };
      lazygit.enable = true;
      lsp = {
        enable = true;
        servers = lspServers;
      };
      nvim-autopairs.enable = true;
      rainbow-delimiters.enable = true;
      smart-splits.enable = true;
      telescope = {
        enable = true;
        extensions = {
          file-browser.enable = true;
          fzf-native.enable = true;
          ui-select.enable = true;
        };
        keymaps = telescopeKeymaps;
      };
      treesitter = {
        enable = true;
        grammarPackages = treesitterGrammars;
      };
      web-devicons.enable = true;
      which-key.enable = true;
    };
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
  };
}

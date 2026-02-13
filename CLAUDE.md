# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Development Commands

All commands use `just` (command runner):

```bash
just darwin        # Build and deploy configuration (darwin-rebuild switch)
just darwin-debug  # Deploy with verbose output and trace for debugging
just fmt           # Format all .nix files with alejandra
just up            # Update all flake inputs
just upp <input>   # Update specific flake input
just clean         # Remove generations older than 7 days
just gc            # Garbage collect unused nix store entries
just history       # View system profile generations
just repl          # Open Nix REPL
```

**Testing**: No automated tests. Validation is `just darwin` completing without errors. For risky changes, dry-run with:
```bash
nix build .#darwinConfigurations.ogasawara.system --show-trace   # Mac mini M4
nix build .#darwinConfigurations.tanegashima.system --show-trace  # MacBook Air M1
```

## Architecture

This is a nix-darwin configuration for macOS (aarch64-darwin) using flakes, home-manager, and nixvim.

**Entry point**: `flake.nix` defines inputs (nixpkgs-unstable, home-manager, nix-darwin, nixvim) and uses `mkDarwinConfig` helper to generate configurations for each host (ogasawara: Mac mini M4, tanegashima: MacBook Air M1). Both share the same module set.

**Module structure**:
- `modules/` - System-level configuration
  - `nix-core.nix` - Nix daemon, garbage collection, unfree packages
  - `system.nix` - macOS defaults (Dock, Finder, Trackpad, Keyboard, hot corners)
  - `apps.nix` - Homebrew and Nix packages (CLI and GUI apps)
  - `host-users.nix` - Hostname and user account
- `home/` - User-level configuration (home-manager)
  - `default.nix` - Entry point, imports all user modules
  - `core.nix` - CLI utilities (ripgrep, jq, fzf, yazi, eza)
  - `shell.nix` - Zsh with direnv
  - `git.nix` - Git with delta pager
  - `nixvim.nix` - Neovim configuration with LSP
  - `starship.nix` - Shell prompt
  - `karabiner.nix` - Keyboard remapping
  - `wezterm.nix` - Terminal emulator
  - `macos/aerospace.nix` - Tiling window manager
- `scripts/` - Utilities (proxy script)

## Coding Conventions

- 2-space indentation for Nix attribute sets
- Options ordered alphabetically where possible
- Run `nix fmt` (alejandra) before committing
- Conventional Commits: `feat:`, `fix:`, `refactor:`, etc.
- New hosts: add entry to `darwinConfigurations` in `flake.nix`; Justfile auto-detects hostname
- Host-specific config: use `lib.mkIf (hostname == "ogasawara") { ... }` in modules

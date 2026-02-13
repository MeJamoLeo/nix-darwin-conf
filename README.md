# Nix Darwin Configuration

macOS (aarch64-darwin) configuration using nix-darwin, home-manager, and nixvim.

## Module Dependency

```mermaid
graph TD
    flake.nix --> nix-core.nix
    flake.nix --> system.nix
    flake.nix --> apps.nix
    flake.nix --> host-users.nix
    flake.nix --> modules/courses/cs3354.nix
    flake.nix --> home-manager

    home-manager --> home/default.nix
    home/default.nix --> shell.nix
    home/default.nix --> core.nix
    home/default.nix --> git.nix
    home/default.nix --> nixvim.nix
    home/default.nix --> starship.nix
    home/default.nix --> wezterm.nix
    home/default.nix --> macos/aerospace.nix
    home/default.nix --> courses/cs3339.nix
    home/default.nix --> courses/cs3354.nix

    subgraph "Flake Inputs"
        nixpkgs-unstable
        nix-darwin
        home-manager-input[home-manager]
        nixvim-input[nixvim]
    end

    subgraph "System Modules (modules/)"
        nix-core.nix
        system.nix
        apps.nix
        host-users.nix
        modules/courses/cs3354.nix
    end

    subgraph "User Modules (home/)"
        home/default.nix
        shell.nix
        core.nix
        git.nix
        nixvim.nix
        starship.nix
        wezterm.nix
        macos/aerospace.nix
        courses/cs3339.nix
        courses/cs3354.nix
    end
```

## Build Flow

```mermaid
flowchart LR
    A[nix build] --> B[darwin-rebuild switch]
    B --> C[System Config]
    B --> D[Home Manager]

    C --> C1[/etc/ files]
    C --> C2[macOS defaults]
    C --> C3[Homebrew bundle]
    C --> C4[Launch Daemons]

    D --> D1[Dotfiles]
    D --> D2[Shell config]
    D --> D3[Activation scripts]
    D --> D4[User packages]
```

## Commands

```bash
just darwin        # Build and deploy configuration
just darwin-debug  # Deploy with verbose output
just fmt           # Format all .nix files
just up            # Update all flake inputs
just upp <input>   # Update specific flake input
just clean         # Remove generations older than 7 days
just gc            # Garbage collect unused nix store entries
just history       # View system profile generations
just repl          # Open Nix REPL
```

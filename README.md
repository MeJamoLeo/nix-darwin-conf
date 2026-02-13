# Nix Darwin Configuration

macOS (aarch64-darwin) configuration using nix-darwin, home-manager, and nixvim.

## Module Dependency

```mermaid
graph TD
    flake["flake.nix<br/>mkDarwinConfig"] --> ogasawara["ogasawara<br/>Mac mini M4"]
    flake --> tanegashima["tanegashima<br/>MacBook Air M1"]

    ogasawara --> modules["Shared Modules"]
    tanegashima --> modules

    modules --> nix-core["nix-core.nix"]
    modules --> system["system.nix"]
    modules --> apps["apps.nix"]
    modules --> host-users["host-users.nix"]
    modules --> mod-cs3354["courses/cs3354.nix"]
    modules --> hm["home-manager"]

    hm --> home-default["home/default.nix"]
    home-default --> shell["shell.nix"]
    home-default --> core["core.nix"]
    home-default --> git["git.nix"]
    home-default --> nixvim["nixvim.nix"]
    home-default --> starship["starship.nix"]
    home-default --> wezterm["wezterm.nix"]
    home-default --> aerospace["macos/aerospace.nix"]
    home-default --> cs3339["courses/cs3339.nix"]
    home-default --> cs3354["courses/cs3354.nix"]

    subgraph "Flake Inputs"
        nixpkgs-unstable
        nix-darwin
        hm-input["home-manager"]
        nixvim-input["nixvim"]
    end

    subgraph "System Modules"
        nix-core
        system
        apps
        host-users
        mod-cs3354
    end

    subgraph "User Modules"
        home-default
        shell
        core
        git
        nixvim
        starship
        wezterm
        aerospace
        cs3339
        cs3354
    end
```

## Build Flow

```mermaid
flowchart LR
    A[nix build] --> B[darwin-rebuild switch]
    B --> C[System Config]
    B --> D[Home Manager]

    C --> C1["etc files"]
    C --> C2["macOS defaults"]
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

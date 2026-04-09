# Red-tape template

This template demonstrates a minimal [red-tape](https://github.com/phaer/red-tape)-based Nix project layout.

## Usage

```sh
nix flake init -t github:leporuid/blueprint#red-tape
nix develop
```

## Structure

- `packages/` — Nix packages
- `hosts/` — host configurations
- `modules/` — reusable NixOS modules
- `users/` — home-manager configurations

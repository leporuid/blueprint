This template demonstrates how to use [leporuid/blueprint](https://github.com/leporuid/blueprint)
with the **generic-users** feature to manage NixOS and nix-darwin hosts alongside per-host
home-manager user configurations.


## Directory Structure

```
.
├── flake.nix
├── devshell.nix                          # default devShells.${system}.default
├── hosts/
│   ├── my-nixos/
│   │   ├── configuration.nix            # NixOS host configuration
│   │   └── users/
│   │       └── alice/
│   │           └── home-configuration.nix   # alice's home-manager config on my-nixos
│   └── my-darwin/
│       ├── darwin-configuration.nix     # nix-darwin host configuration
│       └── users/
│           └── bob/
│               └── home-configuration.nix   # bob's home-manager config on my-darwin
├── modules/
│   ├── home/
│   │   └── example.nix                 # shared home-manager module
│   └── nixos/
│       └── example.nix                 # shared NixOS/darwin module
├── packages/
│   └── example/
│       └── default.nix                 # example package
└── users/
    └── standalone-user/
        └── home-configuration.nix      # standalone home-manager config (no host)
```


## How It Works

### Defining Hosts

Place a `configuration.nix` in `hosts/<hostname>/` to define a **NixOS** host:

```
hosts/my-nixos/configuration.nix   →  nixosConfigurations.my-nixos
```

Place a `darwin-configuration.nix` in `hosts/<hostname>/` to define a **nix-darwin** host:

```
hosts/my-darwin/darwin-configuration.nix   →  darwinConfigurations.my-darwin
```


### Per-Host Users (generic-users)

Place a `home-configuration.nix` under `hosts/<hostname>/users/<username>/` to define a
user's home-manager configuration that is **automatically wired into that host**:

```
hosts/my-nixos/users/alice/home-configuration.nix
```

The generic-users feature:

1. Discovers all `hosts/*/users/*/home-configuration.nix` files
2. Injects `home-manager` into the host configuration automatically
3. Exposes the configuration as `homeConfigurations."alice@my-nixos"`

No manual `home-manager.users` wiring is required in the host configuration.


### Standalone Users

Place a `home-configuration.nix` under `users/<username>/` to define a user who is **not
tied to any specific host**:

```
users/standalone-user/home-configuration.nix   →  homeConfigurations.standalone-user
```

Activate with:

```bash
home-manager switch --flake .#standalone-user
```


### Shared Modules

Modules placed in `modules/nixos/` and `modules/home/` are exposed as flake outputs and
can be imported by any host or user configuration:

| File | Flake output |
|------|-------------|
| `modules/nixos/example.nix` | `inputs.self.nixosModules.example` |
| `modules/home/example.nix` | `inputs.self.homeModules.example` |

Import them in a host or user configuration:

```nix
{ inputs, ... }:
{
  imports = [ inputs.self.nixosModules.example ];
}
```


## Flake Outputs

With this directory structure, blueprint produces the following outputs:

| Output | Value |
|--------|-------|
| `nixosConfigurations.my-nixos` | Full NixOS system with alice's home-manager config |
| `darwinConfigurations.my-darwin` | Full nix-darwin system with bob's home-manager config |
| `homeConfigurations."alice@my-nixos"` | Standalone home-manager config for alice |
| `homeConfigurations."bob@my-darwin"` | Standalone home-manager config for bob |
| `homeConfigurations.standalone-user` | Standalone home-manager config (no host) |
| `nixosModules.example` | Shared NixOS module |
| `homeModules.example` | Shared home-manager module |
| `packages.${system}.example` | Example package |
| `devShells.${system}.default` | Development shell |


## Getting Started

Initialize a new project from this template:

```bash
nix flake init -t github:leporuid/blueprint#red-tape-generic-users
```

Then customize the host and user configurations for your environment.

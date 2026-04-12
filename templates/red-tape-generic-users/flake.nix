{
  description = "blueprint + generic-users: manage NixOS/Darwin hosts with per-host home-manager users";

  # Add all your dependencies here
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";

    # leporuid/blueprint includes the generic-users feature which auto-discovers
    # and wires per-host users defined under hosts/<hostname>/users/<username>/
    blueprint.url = "github:leporuid/blueprint";
    blueprint.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-darwin.url = "github:nix-darwin/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  # Load the blueprint
  outputs = inputs: inputs.blueprint { inherit inputs; };
}

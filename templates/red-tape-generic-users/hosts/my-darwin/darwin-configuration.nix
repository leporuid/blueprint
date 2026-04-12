{ pkgs, inputs, ... }:
{

  # nix-darwin uses the same NixOS module system, so modules/nixos/ are
  # shared between NixOS and Darwin hosts and exposed as nixosModules.*.
  imports = [ inputs.self.nixosModules.example ];

  nixpkgs.hostPlatform = "aarch64-darwin";

  # bob is defined in hosts/my-darwin/users/bob/ and will be automatically
  # wired into home-manager by the generic-users feature.
  users.users.bob.home = /Users/bob;

  system.stateVersion = 6; # initial nix-darwin state
}

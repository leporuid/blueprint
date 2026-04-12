{ pkgs, ... }:
{

  # Example NixOS module shared across all hosts.
  # Available as inputs.self.nixosModules.example in host configurations.

  environment.systemPackages = [
    pkgs.btop
    pkgs.curl
  ];
}

{ pkgs, ... }:
{

  # Example home-manager module shared across all users.
  # Available as inputs.self.homeModules.example in home configurations.

  programs.bash.enable = true;

  home.packages = [
    pkgs.htop
  ];
}

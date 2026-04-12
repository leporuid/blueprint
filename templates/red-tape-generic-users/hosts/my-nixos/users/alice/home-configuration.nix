{ pkgs, inputs, ... }:
{

  imports = [ inputs.self.homeModules.example ];

  home.packages = [ pkgs.ripgrep ];

  home.stateVersion = "24.11"; # initial home-manager state
}

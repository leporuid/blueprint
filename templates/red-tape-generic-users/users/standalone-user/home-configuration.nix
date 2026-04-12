{ pkgs, inputs, ... }:
{

  # Standalone users (defined under users/ rather than hosts/<host>/users/)
  # produce homeConfigurations."standalone-user" outputs that can be activated
  # with `home-manager switch --flake .#standalone-user`.
  #
  # They are not tied to any specific host and can be used on any machine.

  imports = [ inputs.self.homeModules.example ];

  home.packages = [ pkgs.git ];

  home.stateVersion = "24.11"; # initial home-manager state
}

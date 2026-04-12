{ pkgs, inputs, ... }:
{

  imports = [ inputs.self.nixosModules.example ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # alice is defined in hosts/my-nixos/users/alice/ and will be automatically
  # wired into home-manager by the generic-users feature.
  users.users.alice.isNormalUser = true;

  # for testing purposes only, remove on bootable hosts.
  boot.loader.grub.enable = pkgs.lib.mkDefault false;
  fileSystems."/".device = pkgs.lib.mkDefault "/dev/null";

  system.stateVersion = "25.05"; # initial nixos state
}

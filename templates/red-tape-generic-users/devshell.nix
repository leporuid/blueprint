{ pkgs }:
pkgs.mkShell {
  # Add build dependencies
  packages = [
    pkgs.nixos-rebuild
  ];

  # Add environment variables
  env = { };

  # Load custom bash code
  shellHook = ''

  '';
}

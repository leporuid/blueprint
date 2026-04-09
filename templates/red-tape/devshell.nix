{ pkgs }:
pkgs.mkShell {
  packages = [
    pkgs.git
    pkgs.nixfmt-rfc-style
  ];
}

{ pkgs }:
pkgs.writeShellApplication {
  name = "example";
  text = ''
    echo "Hello from the example package!"
  '';
}

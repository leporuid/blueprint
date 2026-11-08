{
  description = "AI-native Nix project";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    blueprint.url = "github:leporuid/blueprint";
  };
  outputs = inputs: inputs.blueprint { inherit inputs; systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ]; };
}

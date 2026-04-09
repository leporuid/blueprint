{
  description = "Red-tape template";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";

    red-tape = {
      url = "github:phaer/red-tape";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: inputs.red-tape.mkFlake {
    inherit inputs;
    src = ./.;
  };
}

{
  description = "description = "Red-tape template with Blueprint compatibility";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";

    blueprint = {
      url = "github:numtide/blueprint";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    red-tape = {
      url = "github:phaer/red-tape";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: (inputs.blueprint { inherit inputs; src = ./.; }) // {
    # Re-export red-tape's mkFlake for direct access
    inherit (inputs.red-tape) mkFlake;
  };
}

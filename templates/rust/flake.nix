{
  description = "Rust project using nixify";
  inputs.nixify.url = "github:rvolosatovs/nixify";
  outputs = { self, nixify, ... }: nixify.lib.rust.mkFlake { src = self; };
}

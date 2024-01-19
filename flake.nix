{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/master";

  outputs = inputs: let
    pkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
    };
  in {
    devShells."x86_64-linux".default = pkgs.mkShell {
      buildInputs = with pkgs; [
        hugo
      ];
    };
  };
}
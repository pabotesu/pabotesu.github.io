{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/master";

  outputs = inputs: let
    # システムごとにパッケージを取得する関数
    pkgsFor = system: import inputs.nixpkgs { inherit system; };
    
    # x86_64-linux用のパッケージ
    pkgsLinux = pkgsFor "x86_64-linux";
    
    # aarch64-darwin用のパッケージ
    pkgsDarwin = pkgsFor "aarch64-darwin";
  in {
    # Linux用の開発環境
    devShells."x86_64-linux".default = pkgsLinux.mkShell {
      buildInputs = with pkgsLinux; [
        hugo
      ];
    };
    
    # macOS (Apple Silicon)用の開発環境
    devShells."aarch64-darwin".default = pkgsDarwin.mkShell {
      buildInputs = with pkgsDarwin; [
        hugo
      ];
    };
  };
}

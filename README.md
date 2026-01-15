# wlib

Nix wrapper library inspired by
[wrapper-manager](https://github.com/viperML/wrapper-manager),
[wrappers](https://github.com/Lassulus/wrappers), and
[nix-wrapper-modules](https://github.com/BirdeeHub/nix-wrapper-modules).

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    wlib = {
      url = "github:nathanielyoon/wlib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    { nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs.wlib = inputs.wlib.lib.${system}.wlib;
        modules = [
          ({ pkgs, wlib, ... }: {
            environment.systemPackages = [
              (wlib.eval pkgs.bat {
                env.BAT_CONFIG_PATH = wlib.file "bat-config" "text" {
                  "--style" = "plain";
                  "--paging" = "never";
                };
              })
            ];
          })
        ];
      };
    }
}
```

{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs =
    { self, nixpkgs }:
    {
      lib = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          inherit (pkgs) lib;
          types = {
            value = lib.types.nullOr (
              lib.types.oneOf [
                lib.types.bool
                lib.types.number
                lib.types.str
                lib.types.path
                (lib.types.functionTo (lib.types.functionTo lib.types.str))
              ]
            );
            args = lib.types.listOf lib.types.str;
            file =
              lib.genAttrs [
                "gitIni"
                "ini"
                "iniWithGlobalSection"
                "json"
                "toml"
                "yaml"
              ] (format: (pkgs.formats.${format} { }).type)
              // {
                text =
                  let
                    either = lib.types.either lib.types.str (lib.types.attrsOf types.value);
                  in
                  lib.types.either either (lib.types.listOf either);
              };
          };
          escape = value: "\"${lib.escape [ "\"" "\\" ] (lib.generators.mkValueStringDefault { } value)}\"";
          args =
            flags:
            let
              join = flags."" or " ";
              line =
                if builtins.isFunction join then
                  join
                else
                  name: value: lib.escape [ join ] name + (if value == null then "" else join + escape value);
            in
            removeAttrs flags [ "" ]
            |> builtins.mapAttrs (_: lib.toList)
            |> lib.mapAttrsToList (name: map <| line name)
            |> builtins.concatLists;
          file =
            name: type: value:
            if type == "text" then
              pkgs.writeText name (
                if builtins.isString value then
                  value
                else
                  lib.toList value ++ [ "" ]
                  |> builtins.concatMap (part: if builtins.isAttrs part then args part else lib.toList part)
                  |> builtins.concatStringsSep "\n"
              )
            else
              (pkgs.formats.${type} { }).generate "${name}${if lib.hasSuffix "." name then type else ""}" value;
          core =
            { config, extendModules, ... }:
            {
              options = {
                package = lib.mkOption {
                  description = "Package to wrap.";
                  type = lib.types.package;
                };
                exe = lib.mkOption {
                  description = "Relative path to the package's executable.";
                  type = lib.types.str;
                  default = lib.getExe config.package |> lib.removePrefix (toString config.package);
                };
                name = lib.mkOption {
                  description = "Name of final binary.";
                  type = lib.types.str;
                  default = baseNameOf config.exe;
                };
                inputs = lib.mkOption {
                  description = "Other packages in $PATH.";
                  type = lib.types.listOf lib.types.package;
                  default = [ ];
                };
                above = lib.mkOption {
                  description = "Flags before passed arguments.";
                  type = types.args;
                  default = [ ];
                };
                below = lib.mkOption {
                  description = "Flags after passed arguments.";
                  type = types.args;
                  default = [ ];
                };
                env = lib.mkOption {
                  description = "Environment variables.";
                  type = lib.types.attrsOf types.value;
                  default = { };
                };
                final = lib.mkOption {
                  description = "Wrapped package.";
                  type = lib.types.package;
                  readOnly = true;
                  default =
                    let
                      exe = "${placeholder "out"}/bin/${config.name}";
                      args =
                        [ "${config.package}/${lib.removePrefix "/" config.exe}" ]
                        ++ config.above
                        ++ [ "\"$@\"" ]
                        ++ config.below
                        |> builtins.concatStringsSep " \\\n    ";
                      env = lib.concatMapAttrsStringSep "\n" (name: value: "export ${name}=${escape value}") config.env;
                    in
                    pkgs.symlinkJoin {
                      inherit (config) name;
                      paths = [ config.package ] ++ config.inputs;
                      postBuild = ''
                        rm -f ${exe}
                        cat >${exe} <<'EOF'
                        #!${pkgs.runtimeShell}
                        set -euo pipefail

                        ${env}
                        exec -a ${config.name} ${args}
                        EOF
                        chmod +x ${exe}
                      '';
                    };
                };
              };
            };
          wlib = {
            inherit
              types
              escape
              args
              file
              ;
            wrap =
              package: modules:
              (lib.evalModules {
                specialArgs = { inherit pkgs wlib; };
                modules = [
                  core
                  (if lib.isDerivation package then { inherit package; } else package)
                ]
                ++ lib.toList modules;
              }).config.final;
          };
        in
        {
          inherit wlib;
        }
      );
    };
}

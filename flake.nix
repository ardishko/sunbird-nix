{
  description = "Phoenix (desktop build 2233) with the Sunbird loader, packaged for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux"; # Phoenix only ships linux-x64
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true; # Phoenix and the Sunbird loader are unfree binaries
      };
      sources = builtins.fromJSON (builtins.readFile ./sources.json);
    in
    {
      packages.${system} = rec {
        phoenix = pkgs.callPackage ./pkgs/phoenix.nix { inherit sources; };
        sunbird-loader = pkgs.callPackage ./pkgs/sunbird-loader.nix { inherit sources; };
        sunbird = pkgs.callPackage ./pkgs/sunbird.nix { inherit phoenix sunbird-loader; };
        sunbird-mutable = sunbird.override { loaderMode = "mutable"; };
        default = sunbird;
      };

      apps.${system} = {
        default = {
          type = "app";
          program = "${self.packages.${system}.sunbird}/bin/sunbird";
        };
        gate-only = {
          type = "app";
          program = "${self.packages.${system}.sunbird}/bin/sunbird-gate-only";
        };
        phoenix = {
          type = "app";
          program = "${self.packages.${system}.phoenix}/bin/phoenix";
        };
      };

      overlays.default = final: prev: {
        inherit (self.packages.${system})
          phoenix
          sunbird-loader
          sunbird
          sunbird-mutable
          ;
      };

      nixosModules.default =
        { config, lib, ... }:
        let
          cfg = config.programs.sunbird;
        in
        {
          options.programs.sunbird = {
            enable = lib.mkEnableOption "Phoenix with the Sunbird loader";
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${system}.sunbird;
              description = "Sunbird package (set to phoenix for the plain client).";
            };
          };
          config = lib.mkIf cfg.enable {
            environment.systemPackages = [ cfg.package ];
          };
        };

      formatter.${system} = pkgs.nixfmt;
    };
}

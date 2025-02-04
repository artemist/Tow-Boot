{ config, lib, ... }:

let
  inherit (lib)
    mkOption
    types
  ;
in
{
  imports = [
    ./hardware
    ./tow-boot
    ./build.nix
    ./device.nix
    ./helpers.nix
    ./kconfig.nix
    ./overlays.nix
    ./system.nix
    ./temp.nix # legacy builder support during migration
  ];

  options = {
    verbose = mkOption {
      description = ''
        Used to print more information during the system evaluation.

        Build results **should not be different**. If they are, it is a bug.
      '';
      type = types.bool;
      default = false;
      internal = true;
    };
    helpers = {
    };
  };
}

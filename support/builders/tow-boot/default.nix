# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: Copyright (c) 2003-2021 Eelco Dolstra and the Nixpkgs/NixOS contributors
# SPDX-FileCopyrightText: Copyright (c) 2021 Samuel Dionne-Riel and respective contributors
#
# This builder function is heavily based off of the buildUBoot function from
# Nixpkgs.
#
# It does not need to be kept synchronized.
#
# Origin: https://github.com/NixOS/nixpkgs/blob/a4b21085fa836e545dcbd905e27329563c389c6e/pkgs/misc/uboot/default.nix

{ stdenv
, lib
, fetchurl
, fetchpatch
, fetchFromGitHub
, bc
, bison
, dtc
, flex
, openssl
, swig
, meson-tools
, armTrustedFirmwareAllwinner
, armTrustedFirmwareRK3328
, armTrustedFirmwareRK3399
, armTrustedFirmwareS905
, buildPackages
, runCommandNoCC
}:

{
    extraConfig ? ""
  , makeFlags ? []

  , filesToInstall ? []
  , defconfig
  , patches ? []
  , meta ? {}

  # The following options should only be disabled when it breaks a build.
  , withLogo ? true
  , withTTF ? false # Too many issues for the time being...
  , withPoweroff ? true
  , ...
} @ args:

let
  uBootVersion = "2021.04";

  # For now, monotonically increasing number.
  # Represents released versions.
  towBootIdentifier = "001";

  # To produce the bitmap image:
  #     convert input.png -depth 8 -colors 256 -compress none output.bmp
  # This tiny build produces the `.gz` file that will actually be used.
  compressedLogo = runCommandNoCC "uboot-logo" {} ''
    mkdir -p $out
    cp ${../../../assets/tow-boot-splash.bmp} $out/logo.bmp
    (cd $out; gzip -9 -k logo.bmp)
  '';
in
stdenv.mkDerivation ({
  pname = "tow-boot-${defconfig}";

  version = "${uBootVersion}-${towBootIdentifier}";

  src = fetchurl {
    url = "ftp://ftp.denx.de/pub/u-boot/u-boot-${uBootVersion}.tar.bz2";
    sha256 = "06p1vymf0dl6jc2xy5w7p42mpgppa46lmpm2ishmgsycnldqnhqd";
  };

  patches = [
    ./patches/0001-Tow-Boot-Provide-opinionated-boot-flow.patch
    ./patches/0001-Tow-Boot-treewide-Identify-as-Tow-Boot.patch
    ./patches/0001-bootmenu-improvements.patch
    ./patches/0001-drivers-video-Add-dependency-on-GZIP.patch
    ./patches/0001-splash-improvements.patch
    ./patches/0001-Libretech-autoboot-correct-config-naming-only-allow-.patch
  ] ++ patches;

  postPatch = ''
    patchShebangs tools
    patchShebangs arch/arm/mach-rockchip
  '';

  nativeBuildInputs = [
    bc
    bison
    dtc
    flex
    openssl
    (buildPackages.python3.withPackages (p: [
      p.libfdt
      p.setuptools # for pkg_resources
    ]))
    swig
  ];

  depsBuildBuild = [ buildPackages.stdenv.cc ];

  hardeningDisable = [ "all" ];

  makeFlags = [
    "DTC=dtc"
    "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
  ] ++ lib.optionals withLogo [
    # Even though the build will actively use the compressed bmp.gz file,
    # we have to provide the uncompressed file and file name here.
    "LOGO_BMP=${compressedLogo}/logo.bmp"
  ] ++ makeFlags
  ;

  extraConfig = ''
    # Identity
    # --------

    CONFIG_IDENT_STRING="${towBootIdentifier}"

    # Behaviour
    # ---------

    # Boot menu required for the menu (duh)
    CONFIG_CMD_BOOTMENU=y

    # Boot menu and default boot configuration

    # Gives *some* time for the user to act.
    # Though an already-knowledgeable user will know they can use the key
    # before the message is shown.
    # Conversely, CTRL+C can cancel the default boot, showing the menu as
    # expected In reality, this gives us MUCH MORE slop in the time window
    # than 1 second.
    CONFIG_BOOTDELAY=1

    # This would be escape, but the USB drivers don't really play well and
    # escape doesn't work from the keyboard.
    CONFIG_AUTOBOOT_MENUKEY=27

    # So we'll fake that using CTRL+C is what we want...
    # It's only a side-effect.
    CONFIG_AUTOBOOT_PROMPT="Press CTRL+C for the boot menu."

    # And this ends up causing the menu to be used on CTRL+C (or escape)
    CONFIG_AUTOBOOT_USE_MENUKEY=y

    ${lib.optionalString withPoweroff ''
    # Additional commands
    CONFIG_CMD_CLS=y
    CONFIG_CMD_POWEROFF=y
    ''}

    # Looks
    # -----

    # Ensures white text on black background
    CONFIG_SYS_WHITE_ON_BLACK=y

    ${lib.optionalString withTTF ''
    # Truetype console configuration
    CONFIG_CONSOLE_TRUETYPE=y
    CONFIG_CONSOLE_TRUETYPE_NIMBUS=y
    CONFIG_CONSOLE_TRUETYPE_SIZE=26
    # Ensure the chosen font is used
    CONFIG_CONSOLE_TRUETYPE_CANTORAONE=n
    CONFIG_CONSOLE_TRUETYPE_ANKACODER=n
    CONFIG_CONSOLE_TRUETYPE_RUFSCRIPT=n
    ''}

    ${lib.optionalString withLogo ''
    # For the splash screen
    CONFIG_CMD_BMP=y
    CONFIG_SPLASHIMAGE_GUARD=y
    CONFIG_SPLASH_SCREEN=y
    CONFIG_SPLASH_SCREEN_ALIGN=y
    CONFIG_VIDEO_BMP_GZIP=y
    CONFIG_VIDEO_BMP_LOGO=y
    CONFIG_VIDEO_BMP_RLE8=n
    CONFIG_BMP_16BPP=y
    CONFIG_BMP_24BPP=y
    CONFIG_BMP_32BPP=y
    CONFIG_SPLASH_SOURCE=n
    ''}

    # Additional configuration (if needed)
    ${extraConfig}
  '';

  # Inject defines for things lacking actual configuration options.
  NIX_CFLAGS_COMPILE = lib.optionals withLogo [
    "-DCONFIG_SYS_VIDEO_LOGO_MAX_SIZE=${toString (1920*1080*4)}"
    "-DCONFIG_VIDEO_LOGO"
  ];

  passAsFile = [ "extraConfig" ];

  configurePhase = ''
    runHook preConfigure
    make ${defconfig}
    cat $extraConfigPath >> .config
    runHook postConfigure
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp .config $out
    ${lib.optionalString (builtins.length filesToInstall > 0) ''
    cp ${lib.concatStringsSep " " filesToInstall} $out
    ''}
    runHook postInstall
  '';

  # make[2]: *** No rule to make target 'lib/efi_loader/helloworld.efi', needed by '__build'.  Stop.
  enableParallelBuilding = false;

  dontStrip = true;

  meta = with lib; {
    homepage = "https://github.com/Tow-Boot/Tow-Boot";
    description = "Your boring SBC firmware";
    license = licenses.gpl2;
    maintainers = with maintainers; [ samueldr ];
  } // meta;

} // removeAttrs args [ "meta" "patches" "makeFlags" "extraConfig" ])
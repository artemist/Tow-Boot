{ stdenv, lib, fetchgit }:

stdenv.mkDerivation {
  pname = "imx8mm-firmware";
  version = "2019-10-24";

  src = fetchgit {
    url = "https://coral.googlesource.com/imx-firmware/";
    rev = "8510b4a900368694dd2781b82b49b556779fd9ec";
    sha256 = "sha256-8wQpAkbgQ+HXUDcD8p4rpwFTfkywo0rHROl2T3MJ7aE=";
  };

  installPhase = ''
    mkdir -p $out
    mv -t $out/ imx8mm/lpddr4* imx8mm/signed_*.bin
  '';

  dontFixup = true;

  meta = with lib; {
    description = "Firmware used to initialize video and memory controllers in U-Boot on the i.MX8M Mini";
    license = licenses.unfreeRedistributableFirmware;
    maintainers = with maintainers; [ artemist ];
  };
}

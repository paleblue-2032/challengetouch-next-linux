{ pkgs ? import <nixpkgs> { } }:
pkgs.buildFHSEnv {
    name = "cpad-kernel-build";
    targetPkgs = pkgs: with pkgs; [
      gcc gcc.cc.lib gnumake
      flex bison gperf bc
      zip unzip cpio gzip xz zstd bzip2
      zlib zlib.dev
      ncurses5
      openssl openssl.dev
      python3 python3Packages.setuptools
      perl which file rsync wget curl git
      dtc elfutils
      ccache
      pkg-config
      glibc glibc.dev glibc.static
      vim # provides xxd
    ];
    multiPkgs = pkgs: with pkgs; [ zlib ncurses5 ];
    profile = ''
      export CCACHE_DIR="$HOME/.ccache-cpad"
      umask 022
    '';
    runScript = "bash";
}

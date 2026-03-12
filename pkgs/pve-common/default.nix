{
  lib,
  stdenv,
  fetchgit,
  fetchurl,
  bash,
  coreutils,
  diffutils,
  iproute2,
  perl540,
  glibc,
  openvswitch,
  pciutils,
  proxmox-backup-client,
  systemd,
  tzdata,
  usbutils,
  mimebase32,
  mimebase64,
  replaceVars,
  pve-update-script,
}:

let
  cryptOpenSSLRSA = perl540.pkgs.CryptOpenSSLRSA.overrideAttrs (_old: {
    version = "0.33";
    src = fetchurl {
      url = "mirror://cpan/authors/id/T/TO/TODDR/Crypt-OpenSSL-RSA-0.33.tar.gz";
      hash = "sha256-vb5jD21vVAMldGrZmXcnKshmT/gb0Z8K2rptb0Xv2GQ=";
    };
  });

  perlDeps = with perl540.pkgs; [
    AnyEvent
    Carp
    Clone
    cryptOpenSSLRSA
    CryptOpenSSLRandom
    PathTools
    DataDumper
    TimeDate
    DevelCycle
    #DigestMD5
    DigestSHA
    Encode
    EncodeLocale
    #Exporter
    FilePath
    #FileTemp
    FilesysDf
    GetoptLong
    HTTPMessage
    IOStringy
    IO
    IOSocketIP
    JSON
    #libwwwperl
    LinuxInotify2
    LWPProtocolHttps
    ScalarListUtils
    mimebase32
    mimebase64
    NetDBus
    NetIP
    perlldap
    NetSSLeay
    NetAddrIP
    Socket
    #Storable
    StringShellQuote
    SysSyslog
    TextParsewords
    #TextTabsWrap
    TimeHiRes
    TimeLocal
    URI
    YAMLLibYAML
  ];
in

perl540.pkgs.toPerlModule (
  stdenv.mkDerivation rec {
    pname = "pve-common";
    version = "9.1.7";

    src = fetchgit {
      url = "git://git.proxmox.com/git/${pname}.git";
      rev = "9c1d4f469b8baaaa1cb73c335d2be08925142d1a";
      hash = "sha256-v28wjqVX3iviI3Ngb8PZqz3tlMAxshyu/kSfeJwrYxw=";
    };

    sourceRoot = "${src.name}/src";

    patches = [
      (replaceVars ./0001-ss_fix_path.patch {
        sspath = "${iproute2}/bin/";
      })

      (replaceVars ./0003-pci-id-path.patch {
        pciutils = "${pciutils}";
      })
    ];

    propagatedBuildInputs = [
      bash
      coreutils
      diffutils
      iproute2
      proxmox-backup-client
      systemd
      usbutils
    ]
    ++ perlDeps;

    makeFlags = [
      "PREFIX=$(out)"
      "PERLDIR=$(out)/${perl540.libPrefix}/${perl540.version}"
    ];

    postInstall =
      let
        includeHeaders =
          "{sys,bits,}/syscall.h "
          + (
            if (stdenv.buildPlatform.system == "x86_64-linux") then
              "asm/unistd{,_64}.h"
            else
              "asm{,-generic}/{unistd,bitsperlong}.h"
          );
      in
      ''
        for h in ${includeHeaders}; do
          ${perl540}/bin/h2ph -d $out ${glibc.dev}/include/$h
          mkdir -p $out/include/$(dirname $h)
          mv $out${glibc.dev}/include/''${h%.h}.ph $out/include/$(dirname $h)
        done
        mv $out/_h2ph_pre.ph $out/include
        cp -r $out/include/* $out/${perl540.libPrefix}/${perl540.version}
        rm -r $out/{nix,include}
      '';

    postFixup = ''
      find $out/lib -type f | xargs sed -i \
        -e "/ENV{'PATH'}/d" \
        -e "s|ovs-vsctl|${openvswitch}/bin/ovs-vsctl|" \
        -e "s|/usr/share/zoneinfo|${tzdata}/share/zoneinfo|" \
        -Ee "s|(/usr)?/s?bin/||"
    '';

    passthru.updateScript = pve-update-script {
      extraArgs = [
        "--deb-name"
        "libpve-common-perl"
      ];
    };

    meta = with lib; {
      description = "Proxmox Project's Common Perl Code";
      homepage = "https://git.proxmox.com/?p=pve-common.git";
      license = licenses.agpl3Plus;
      maintainers = with maintainers; [
        camillemndn
        julienmalka
      ];
      platforms = platforms.linux;
    };
  }
)

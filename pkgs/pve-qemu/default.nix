{
  common-updater-scripts,
  lib,
  nix,
  qemu,
  fetchurl,
  fetchgit,
  proxmox-backup-qemu,
  perl540,
  pve-update,
  writeShellScript,
}:

let
  pveSrc = fetchgit {
    url = "git://git.proxmox.com/git/pve-qemu.git";
    rev = "a7c7a6b2b1aa75360d914b252dfcb05506ce590b";
    hash = "sha256-b3rzpOF7PBK3uZBksPLHbkxR8/GQ8drwWEbo7hmYniM=";
    fetchSubmodules = false;
  };

  perlDeps = with perl540.pkgs; [ JSON ];
  perlEnv = perl540.withPackages (_: perlDeps);
in
(qemu.overrideAttrs (
  finalAttrs: old:
  let
    qemuVersion = lib.head (lib.splitString "-" finalAttrs.version);
  in
  {
    pname = "pve-qemu";
    version = "10.1.2-7";

    src = fetchurl {
      url = "https://download.qemu.org/qemu-${qemuVersion}.tar.xz";
      hash = "sha256-nXXzMcGly5tuuP2fZPVj7C6rNGyCLLl/izXNgtPxFHk=";
    };

    patches =
      let
        series = builtins.readFile "${pveSrc}/debian/patches/series";
        patchList = builtins.filter (patch: patch != "") (lib.splitString "\n" series);
        patchPathsList = map (patch: "${pveSrc}/debian/patches/${patch}") patchList;
      in
      old.patches ++ patchPathsList;

    sourceRoot = "qemu-${qemuVersion}";

    buildInputs = old.buildInputs ++ [ proxmox-backup-qemu ];

    postPatch =
      old.postPatch
      + ''
        cp ${proxmox-backup-qemu}/lib/proxmox-backup-qemu.h .
      '';

    # Generate cpu flag files and machine versions json
    # This is done in /debian/rules of pve-qemu, and needed by pve-qemu-server
    postInstall = old.postInstall + ''
      $out/bin/qemu-system-x86_64 -cpu help \
        | ${perlEnv}/bin/perl ${pveSrc}/debian/parse-cpu-flags.pl > $out/share/qemu/recognized-CPUID-flags-x86_64
      $out/bin/qemu-system-x86_64 -machine help \
        | ${perlEnv}/bin/perl ${pveSrc}/debian/parse-machines.pl > $out/share/qemu/machine-versions-x86_64.json
    '';

    passthru = (old.passthru or { }) // {
      inherit pveSrc;

      updateScript = writeShellScript "update-pve-qemu" ''
        set -euo pipefail

        attr="''${1:-''${UPDATE_NIX_ATTR_PATH:-pve-qemu}}"

        ${lib.getExe pve-update} \
          --deb-name pve-qemu-kvm \
          --source-key pveSrc \
          "$attr"

        version="$(${nix}/bin/nix eval --raw ".#$attr.version")"
        ${common-updater-scripts}/bin/update-source-version \
          "$attr" \
          "$version" \
          --source-key=src \
          --ignore-same-version
      '';
    };

    meta.position = dirOf ./.;
  }
)).override
  {
    glusterfsSupport = true;
    enableDocs = false;
    cephSupport = true;
  }

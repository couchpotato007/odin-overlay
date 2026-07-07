final: prev:
let
  versions = import ./versions.nix;
  mkOdin =
    {
      rev,
      sha256,
      patch,
      ...
    }:
    let
      llvmPackages = prev.llvmPackages_18;
      inherit (llvmPackages) stdenv;
    in
    stdenv.mkDerivation (finalAttrs: {
      pname = "odin";
      version = rev;
      src = prev.fetchFromGitHub {
        owner = "odin-lang";
        repo = "Odin";
        rev = rev;
        hash = sha256;
      };
      patches = [ patch ];
      postPatch = ''
        rm -rf vendor/raylib/{linux,macos,macos-arm64,wasm,windows}
        patchShebangs --build build_odin.sh
      '';
      env.LLVM_CONFIG = prev.lib.getExe' llvmPackages.llvm.dev "llvm-config";
      dontConfigure = true;
      buildFlags = [ "release" ];

      nativeBuildInputs = [
        prev.makeBinaryWrapper
        prev.which
      ];

      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        cp odin $out/bin/odin
        mkdir -p $out/share
        cp -r {base,core,vendor,shared} $out/share
        wrapProgram $out/bin/odin \
          --prefix PATH : ${
            prev.lib.makeBinPath (
              with llvmPackages;
              [
                bintools
                llvm
                clang
                lld
              ]
            )
          } \
          --set-default ODIN_ROOT $out/share
        make -C "$out/share/vendor/cgltf/src/"
        make -C "$out/share/vendor/stb/src/"
        make -C "$out/share/vendor/miniaudio/src/"
        runHook postInstall
      '';

      meta = {
        description = "Fast, concise, readable, pragmatic and open sourced programming language";
        homepage = "https://odin-lang.org/";
        license = prev.lib.licenses.bsd3;
        mainProgram = "odin";
        platforms = prev.lib.platforms.unix;
        broken = stdenv.hostPlatform.isMusl;
      };
    });
in
{
  odin-bin = {
    stable = mkOdin (versions.stable // { patch = ./patches/stable-system-raylib.patch; });
    nightly = mkOdin (versions.nightly // { patch = ./patches/nightly-system-raylib.patch; });
  };
}

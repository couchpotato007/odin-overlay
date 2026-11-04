final: prev: let
  inherit (prev) lib;

  sources = lib.importJSON ./sources.json;

  # First llvmPackages_N from `versions` (preferred first) that still exists in
  # nixpkgs. Removed versions are throwing aliases, hence the tryEval.
  pickLlvm = versions: let
    available = n: let
      name = "llvmPackages_${toString n}";
    in
      prev ? ${name} && (builtins.tryEval prev.${name}).success;
    found = lib.findFirst available null versions;
  in
    if found == null
    then null
    else prev."llvmPackages_${toString found}";

  # "dev-2024-05", "dev-2026-11a", "0-unstable-2026-11-03"  ->  "2024-05", ...
  versionDate = version: let
    m = builtins.match ".*([0-9]{4}-[0-9]{2}).*" version;
  in
    if m == null
    then "unknown"
    else builtins.head m;

  mkOdin = {
    version,
    rev,
    hash,
    llvmPackages,
    ...
  }: let
    inherit (llvmPackages) stdenv;
  in
    stdenv.mkDerivation {
      pname = "odin";
      inherit version;

      src = prev.fetchFromGitHub {
        owner = "odin-lang";
        repo = "Odin";
        inherit rev hash;
      };

      postPatch = ''
        # Use the system raylib/raygui instead of the bundled prebuilt
        # binaries: GLFW in those tries to dlopen Xlib from FHS paths.
        # Rewrites every `"(../)linux*/libraylib…"( when X else "…")` style
        # import to "system:raylib", which works across all Odin versions.
        find vendor/raylib -name '*.odin' -exec sed -E -i \
          's#"(\.\./)?(linux|linux-arm64|macos|macos-arm64)/lib(raylib|raygui)[^"]*"( when [A-Za-z_]+ else "[^"]*")?#"system:\3"#g' {} +
        if grep -rqE '"(\.\./)?(linux|linux-arm64|macos|macos-arm64)/lib' vendor/raylib; then
          echo "error: unpatched bundled raylib import left in vendor/raylib" >&2
          grep -rnE '"(\.\./)?(linux|linux-arm64|macos|macos-arm64)/lib' vendor/raylib >&2
          exit 1
        fi
        rm -rf vendor/raylib/{linux,linux-arm64,macos,macos-arm64,windows}

        # Without .git the version would be derived from the build date.
        substituteInPlace build_odin.sh \
          --replace-fail '$(date +"%Y-%m")' '${versionDate version}'

        patchShebangs --build build_odin.sh
      '';

      env.LLVM_CONFIG = lib.getExe' llvmPackages.llvm.dev "llvm-config";

      dontConfigure = true;

      buildFlags = ["release"];

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
          lib.makeBinPath (with llvmPackages; [
            bintools
            llvm
            clang
            lld
          ])
        } \
          --set-default ODIN_ROOT $out/share

        # Build the bundled C libraries. Older releases ship a Makefile,
        # newer ones build_*.sh scripts. (vendor/box3d's build.sh also builds
        # wasm, which the cc-wrapper can't do, so it is skipped like in nixpkgs.)
        patchShebangs --build $out/share/vendor
        for src in $out/share/vendor/*/src; do
          scripts=()
          for s in "$src"/build_*.sh; do
            [ -f "$s" ] || continue
            case "$s" in *android*) continue ;; esac
            scripts+=("$s")
          done
          if [ ''${#scripts[@]} -gt 0 ]; then
            for s in "''${scripts[@]}"; do
              echo "building vendor library: $s"
              (cd "$src" && ODIN_ROOT=$out/share bash "$s")
            done
          elif [ -f "$src/Makefile" ]; then
            echo "building vendor library: $src/Makefile"
            make -C "$src"
          fi
        done

        runHook postInstall
      '';

      passthru = {inherit llvmPackages;};

      meta = {
        description = "Fast, concise, readable, pragmatic and open sourced programming language";
        homepage = "https://odin-lang.org/";
        license = lib.licenses.zlib;
        mainProgram = "odin";
        platforms = lib.platforms.unix;
        broken = stdenv.hostPlatform.isMusl;
      };
    };

  mkOls = {
    version,
    rev,
    hash,
    odin,
    ...
  }:
    prev.stdenv.mkDerivation {
      pname = "ols";
      inherit version;

      src = prev.fetchFromGitHub {
        owner = "DanielGavin";
        repo = "ols";
        inherit rev hash;
      };

      postPatch = ''
        substituteInPlace build.sh \
          --replace-quiet "-microarch:native" ""
        patchShebangs build.sh odinfmt.sh
      '';

      nativeBuildInputs = [prev.makeBinaryWrapper];

      buildInputs = [
        odin
        prev.git
      ];

      buildPhase = ''
        runHook preBuild

        ./build.sh && ./odinfmt.sh

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        install -Dm755 ols odinfmt -t $out/bin/
        wrapProgram $out/bin/ols \
          --set-default ODIN_ROOT ${odin}/share \
          --set-default OLS_BUILTIN_FOLDER ${odin}/share/base/builtin

        runHook postInstall
      '';

      passthru = {inherit odin;};

      meta = {
        inherit (odin.meta) platforms;
        description = "Language server for the Odin programming language";
        homepage = "https://github.com/DanielGavin/ols";
        license = lib.licenses.mit;
        mainProgram = "ols";
      };
    };

  # Every source entry whose LLVM requirements nixpkgs can still satisfy.
  odinVersions = lib.filterAttrs (_: v: v != null) (lib.mapAttrs (
      _: src: let
        llvmPackages = pickLlvm (src.llvm or [18]);
      in
        if llvmPackages == null
        then null
        else mkOdin (src // {inherit llvmPackages;})
    )
    sources.odin);

  releaseTags = builtins.filter (n: n != "nightly") (builtins.attrNames odinVersions);
  # Tags are dev-YYYY-MM[a-z], so lexicographic order is chronological.
  latestTag = lib.last (lib.sort (a: b: a < b) releaseTags);

  # An ols release often breaks with newer Odin core libraries, so build it
  # with the newest Odin release from the same month as the ols tag or earlier.
  odinForOls = olsSrc: let
    date = versionDate olsSrc.version;
    older = builtins.filter (t: versionDate t <= date) releaseTags;
  in
    odinVersions.${
      if older == []
      then latestTag
      else lib.last (lib.sort (a: b: a < b) older)
    };
in {
  odin-bin =
    odinVersions
    // {
      stable = odinVersions.${latestTag};
    };

  ols-bin = {
    stable = mkOls (sources.ols.stable // {odin = odinForOls sources.ols.stable;});
    nightly = mkOls (sources.ols.nightly // {odin = final.odin-bin.nightly;});
  };
}

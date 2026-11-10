{
  description = "standard-clj: Standard Clojure Style formatter, implemented in Haxe";

  inputs.nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";

  outputs =
    { nixpkgs, self }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      src = nixpkgs.lib.fileset.toSource {
        root = ./.;
        fileset = nixpkgs.lib.fileset.unions [
          ./cli
          ./cli.hxml
          ./lib
          ./test
          ./test.hxml
          ./tests
        ];
      };
    in
    {
      checks = forAllSystems (pkgs: {
        # Reads the log and status written by test-run, so that a failure
        # is cached and its log is easy to reach.
        tests =
          let
            run = self.packages.${pkgs.stdenv.hostPlatform.system}.test-run;
          in
          pkgs.runCommand "tests" { } ''
            cat ${run}/log
            test "$(cat ${run}/status)" = 0
            touch $out
          '';
      });

      packages = forAllSystems (pkgs: {
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.standard-clj;

        standard-clj = pkgs.stdenv.mkDerivation {
          pname = "standard-clj";
          version = "0.0.0";
          inherit src;
          nativeBuildInputs = [
            pkgs.haxe
            pkgs.makeWrapper
          ];
          buildPhase = ''
            runHook preBuild
            haxe cli.hxml
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            install -Dm644 standard-clj.n $out/lib/standard-clj/standard-clj.n
            makeWrapper ${pkgs.neko}/bin/neko $out/bin/standard-clj \
              --add-flags $out/lib/standard-clj/standard-clj.n
            runHook postInstall
          '';
          meta.mainProgram = "standard-clj";
        };

        # Runs the tests. Always succeeds; the log and exit status are
        # written to the output and judged by checks.tests.
        test-run = pkgs.runCommand "test-run" { nativeBuildInputs = [ pkgs.haxe ]; } ''
          mkdir -p $out
          cp -r ${src}/. work
          chmod -R u+w work
          cd work
          export HOME=$TMPDIR
          set +e
          haxe test.hxml --run Main tests/upstream tests/local > $out/log 2>&1
          echo $? > $out/status
        '';
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.haxe
            pkgs.just
            pkgs.neko
          ];
        };
      });
    };
}

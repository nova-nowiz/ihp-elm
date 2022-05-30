{
  description = "docker build for ihp";

  inputs = {
    # nixpkgs.url = "nixos";
    nixpkgs-ihp.url = "nixpkgs/38da06c69f821af50323d54b28d342cc3eb42891";
    flake-utils.url = "github:numtide/flake-utils";
    ihp = {
      url = "github:digitallyinduced/ihp/6891072c3499a3e4417504eea9e95a7be7dce90d";
      flake = false;
    };
  };

  outputs = inputs @ { self, nixpkgs, nixpkgs-ihp, flake-utils, ihp, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        p = {
          n = import nixpkgs-ihp { inherit system; };
          ihp-elm = {optimized ? false}: (import "${ihp}/NixSupport/default.nix" {
            inherit optimized;
            inherit ihp;
            haskellDeps = p: with p; [
              cabal-install
              base
              wai
              text
              hlint
              p.ihp
            ];
            otherDeps = p: with p; [
              # Native dependencies, e.g. imagemagick
              nodejs
              elmPackages.elm
            ];
            projectPath = ./.;
            additionalNixpkgsOptions.pkgs = p.pkgs;
          }).overrideAttrs (oldAttrs: rec {
            src = p.n.nix-gitignore.gitignoreSource [] self;
          });
          pkgs =
            let
              compiler = "ghc8107";
              haskellPackagesDir = "${self}/Config/nix/haskell-packages/.";
              dontCheckPackages = ["mmark" "mmark-ext"];
              doJailbreakPackages = ["haskell-to-elm"];
              dontHaddockPackages = [];
            in import nixpkgs-ihp {
            inherit system;
            config =
            let
              generatedOverrides = haskellPackagesNew: haskellPackagesOld:
                let
                  toPackage = dir: file: _: {
                    name = builtins.replaceStrings [ ".nix" ] [ "" ] file;

                    value = haskellPackagesNew.callPackage ("${dir}/${file}") {};
                  };
                  makePackageSet = dir: p.n.lib.mapAttrs' (toPackage dir) (builtins.readDir dir);
                in
                  { "ihp" = ((haskellPackagesNew.callPackage "${ihp}/ihp.nix") { }).overrideAttrs (oldAttrs: rec {
                      src = p.n.nix-gitignore.gitignoreSource [] ihp;
                    }); }
                  // (makePackageSet haskellPackagesDir)
                  // (makePackageSet "${ihp}/NixSupport/haskell-packages/.");

              makeOverrides =
                function: names: haskellPackagesNew: haskellPackagesOld:
                let
                  toPackage = name: {
                    inherit name;

                    value = function haskellPackagesOld.${name};
                  };
                in
                  builtins.listToAttrs (map toPackage names);

              composeExtensionsList = p.n.lib.fold p.n.lib.composeExtensions (_: _: {});
            in {
              allowBroken = true;
              packageOverrides = pkgs: rec {
                haskell = pkgs.haskell // {
                  packages = pkgs.haskell.packages // {
                    "${compiler}" =
                      pkgs.haskell.packages."${compiler}".override {
                        overrides = composeExtensionsList [
                          generatedOverrides

                          (makeOverrides pkgs.haskell.lib.dontCheck   dontCheckPackages  )
                          (makeOverrides pkgs.haskell.lib.doJailbreak doJailbreakPackages)
                          (makeOverrides pkgs.haskell.lib.dontHaddock dontHaddockPackages)

                          (self: super: { haskell-language-server = pkgs.haskell.lib.appendConfigureFlag super.haskell-language-server "--enable-executable-dynamic"; })
                          (self: super: { ormolu = if pkgs.system == "aarch64-darwin" then pkgs.haskell.lib.overrideCabal super.ormolu (_: { enableSeparateBinOutput = false; }) else super.ormolu; })
                        ];
                      };
                  };
                };
              };
            };
          };
        };
      in {
        packages = rec {
          ihp-elm-dev = p.ihp-elm {};
          ihp-elm-prod = p.ihp-elm { optimized = true; };
          docker = p.n.dockerTools.buildImage {
            name = "ihp-elm";
            tag = "latest";
            created = "now";
            contents = with p.pkgs; [
              ihp-elm-prod
            ];
            # config.Cmd = [ "npx" "concurrently" "--raw" "RunDevServer" "npm run run-dev-elm" ];
            config = {
              ExposedPorts = {
                "8080" = {};
                "80" = {};
                "8000" = {};
                "8001" = {};
              };
              WorkingDir = "${ihp-elm-prod}/lib";
              Cmd = [ "RunProdServer" ];
            };
          };
        };
      });
}

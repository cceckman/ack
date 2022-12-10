{
  description = "The Amsterdam Compiler Kit";
  # Nixpkgs / NixOS version to use.
  inputs.nixpkgs.url = "nixpkgs/nixos-22.11";
  outputs = { self, nixpkgs }:
    let
      # to work with older version of flakes
      lastModifiedDate = self.lastModifiedDate or self.lastModified or "19700101";
      # Generate a user-friendly version number.
      version = builtins.substring 0 8 lastModifiedDate;
      # System types to support.
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; overlays = [ self.overlay ]; });
      # Build inputs; also for dev shells.
      getBuildInputs = nixpkgs: with nixpkgs; [ which lua flex yacc ninja gcc ];
    in
    {
      # A Nixpkgs overlay; add ACK to the set of packages.
      overlay = final: prev: {
        amsterdam-compiler-kit = with final; stdenv.mkDerivation rec {
          name = "hello-${version}";
          src = ./.;
          buildInputs = getBuildInputs final;
          # ACK uses Ninja under the hood to parallelize builds,
          # but still uses a Makefile for the entry point. To skip Nix's use of
          # ninja:
          #   https://nixos.org/manual/nixpkgs/stable/#ninja
          dontUseNinjaBuild = true;
          dontUseNinjaInstall = true;
          dontUseNinjaCheck = true;
          # Install to Nix's "out" directory.
          makeFlags = [ "PREFIX=$(out)" ];
        };
      };

      devShells = forAllSystems (system:
        let pkgs = nixpkgsFor.${system};
        in {
          default = pkgs.mkShell {
            buildInputs = getBuildInputs pkgs;
          };
        });

      # Provide some binary packages for selected system types.
      packages = forAllSystems (system:
        {
          inherit (nixpkgsFor.${system}) amsterdam-compiler-kit;
        });

      # The default package for 'nix build'. This makes sense if the
      # flake provides only one package or there is a clear "main"
      # package.
      defaultPackage = forAllSystems (system: self.packages.${system}.amsterdam-compiler-kit);

      # Tests run by 'nix flake check' and by Hydra.
      checks = forAllSystems
        (system:
          with nixpkgsFor.${system};

          {
            inherit (self.packages.${system}) amsterdam-compiler-kit;

            # Additional tests, if applicable.
            test = stdenv.mkDerivation {
              name = "ack-test-${version}";
              buildInputs = [ amstersam-compiler-kit ];
              unpackPhase = "true";
              buildPhase = ''
                echo 'running some integration tests'
                [[ $(hello) = 'Hello Nixers!' ]]
              '';
              installPhase = "mkdir -p $out";
            };
          }

          // lib.optionalAttrs stdenv.isLinux {
            # A VM test of the ACK, with QEMU module.
            vmTest =
              with import (nixpkgs + "/nixos/lib/testing-python.nix") {
                inherit system;
              };

              makeTest {
                nodes = {
                  client = { ... }: {
                    # imports = [ self.nixosModules.hello ];
                  };
                };

                testScript =
                  ''
                    start_all()
                    client.wait_for_unit("multi-user.target")
                    client.succeed("hello")
                  '';
              };
          }
        );

    };
}

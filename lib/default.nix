{ inputs, ... }:
# A bunch of helper utilities for the project
let
  bpInputs = inputs;
  nixpkgs = bpInputs.nixpkgs;
  lib = nixpkgs.lib;
in rec {
  # A generator for the top-level attributes of the flake.
  #
  # Designed to work with https://github.com/nix-systems
  mkEachSystem =
    {
      inputs,
      flake,
      systems,
      nixpkgs,
      # We need to treat the packages that are being defined in self differently,
      # since otherwise we trigger infinite recursion when perSystem is defined in
      # terms of the packages defined by self, and self uses perSystem to define
      # its packages.
      # We run into the infrec when trying to filter out packages based on their
      # meta attributes, since that actually requires evaluating the package's derivation
      # and can then in turn change the value of perSystem (by removing packages),
      # which then requires to evaluate the package again, and so on and so forth.
      # To break this cycle, we define perSystem in terms of the filesystem hierarchy,
      # and not based on self.packages, and we don't apply any filtering based on
      # meta attributes yet.
      # The actual self.packages, can then be the filtered set of packages.
      unfilteredPackages,
    }:
    let
      # Memoize the args per system
      systemArgs = lib.genAttrs systems (
        system:
        let
          # Resolve the packages for each input.
          perSystem = lib.mapAttrs (
           name: flake:
            # For self, we need to treat packages differently, see above
            if name == "_" then
               flake.legacyPackages.${system} or { } // flake.packages.${system} or { }
            else
            if name == "self" then
               flake.legacyPackages.${system} or { } // unfilteredPackages.${system}
            else
               flake.legacyPackages.${system} or { } // flake.packages.${system} or { }
          ) inputs;

          # Handle nixpkgs specially.
          pkgs =
            if (nixpkgs.config or { }) == { } && (nixpkgs.overlays or [ ]) == [ ] then
              perSystem.nixpkgs
            else
              import inputs.nixpkgs {
                inherit system;
                config = nixpkgs.config or { };
                overlays = nixpkgs.overlays or [ ];
              };
        in
        lib.makeScope lib.callPackageWith (_: pkgs // {
          inherit
            inputs
            perSystem
            flake
            pkgs
            system
            ;
        })
      );

      eachSystem = f: lib.genAttrs systems (system: f systemArgs.${system});
    in
    {
      inherit systemArgs eachSystem;
    };

  optionalPathAttrs = path: f: lib.optionalAttrs (builtins.pathExists path) (f path);

  # Imports the path and pass the `args` to it if it exists, otherwise, return an empty attrset.
  tryImport = path: args: optionalPathAttrs path (path: import path args);

  # Maps all the toml files in a directory to name -> path.
  importTomlFilesAt =
    path: fn:
    let
      entries = builtins.readDir path;

      # Get paths to toml files, where the name is the basename of the file without the .toml extension
      nixPaths = builtins.removeAttrs (lib.mapAttrs' (
        name: type:
        let
          nixName = builtins.match "(.*)\\.toml" name;
        in
        {
          name = if type == "directory" || nixName == null then "__junk" else (builtins.head nixName);
          value = {
            path = path + "/${name}";
            type = type;
          };
        }
      ) entries) [ "__junk" ];
    in
    lib.optionalAttrs (builtins.pathExists path) (fn nixPaths);

  # Maps all the nix files and folders in a directory to name -> path.
  importDir =
    path: fn:
    let
      entries = builtins.readDir path;

      # Get paths to directories
      onlyDirs = lib.filterAttrs (_name: type: type == "directory") entries;
      dirPaths = lib.mapAttrs (name: type: {
        path = path + "/${name}";
        inherit type;
      }) onlyDirs;

      # Get paths to nix files, where the name is the basename of the file without the .nix extension
      nixPaths = builtins.removeAttrs (lib.mapAttrs' (
        name: type:
        let
          nixName = builtins.match "(.*)\\.nix" name;
        in
        {
          name = if type == "directory" || nixName == null then "__junk" else (builtins.head nixName);
          value = {
            path = path + "/${name}";
            type = type;
          };
        }
      ) entries) [ "__junk" ];

      # Have the nix files take precedence over the directories
      combined = dirPaths // nixPaths;
    in
    lib.optionalAttrs (builtins.pathExists path) (fn combined);

  entriesPath = lib.mapAttrs (_name: { path, type }: path);

  # Prefixes all the keys of an attrset with the given prefix
  withPrefix =
    prefix:
    lib.mapAttrs' (
      name: value: {
        name = "${prefix}${name}";
        value = value;
      }
    );

  filterPlatforms =
    system: attrs:
    lib.filterAttrs (
      _: x:
      if (x.meta.platforms or [ ]) == [ ] then
        true # keep every package that has no meta.platforms
      else
        lib.elem system x.meta.platforms
    ) attrs;

  mkBlueprint' =
    {
      inputs,
      nixpkgs,
      flake,
      src,
      systems,
    }:
    let
      specialArgs = {
        inherit inputs flake;
        self = throw "self was renamed to flake";
      };

      inherit
        (mkEachSystem {
          inherit
            inputs
            flake
            nixpkgs
            systems
            unfilteredPackages
            ;
        })
        eachSystem
        systemArgs
        ;

      perSystemModule =
        { pkgs, ... }:
        {
          _module.args.perSystem = systemArgs.${pkgs.stdenv.hostPlatform.system}.perSystem;
        };

      nixpkgsConfigModule =
        { lib, ... }:
        {
          nixpkgs =
            (lib.optionalAttrs ((nixpkgs.config or { }) != { }) {
              config = nixpkgs.config;
            })
            // (lib.optionalAttrs ((nixpkgs.overlays or [ ]) != [ ]) {
              overlays = nixpkgs.overlays;
            });
        };

      home-manager =
        inputs.home-manager
          or (throw ''home configurations require Home Manager. To fix this, add `inputs.home-manager.url = "github:nix-community/home-manager";` to your flake'');

      devshellFromTOML =
        perSystem: path:
        let
          devshell =
            perSystem.devshell
              or (throw ''Loading TOML devshells requires `inputs.devshell.url = "github:numtide/devshell";` in your flake'');
        in
        devshell.mkShell {
          _module.args = {
            inherit perSystem;
          }; # so that devshell modules can access self exported packages.
          imports = [ (devshell.importTOML path) ];
        };

      # Sets up declared users without any user intervention, and sets the
      # options that most people would set anyway. The module is only returned
      # if home-manager is an input and the host has at least one user with a
      # home manager configuration. With this module, most users will not need
      # to manually configure Home Manager at all.
      mkHomeUsersModule =
        hostname: homeManagerModule:
        let
          module =
            { perSystem, ... }:
            {
              imports = [ homeManagerModule ];
              home-manager.sharedModules = [ perSystemModule ];
              home-manager.extraSpecialArgs = specialArgs;
              home-manager.users = homesNested.${hostname};
              home-manager.useGlobalPkgs = lib.mkDefault true;
              home-manager.useUserPackages = lib.mkDefault true;
            };
        in
        lib.optional (builtins.hasAttr hostname homesNested) module;

      homesGeneric =
        let
          getEntryPath =
            _username: userEntry:
            if builtins.pathExists (userEntry.path + "/home-configuration.nix") then
              userEntry.path + "/home-configuration.nix"
            else
              # If we decide to add users/<username>.nix, it's as simple as
              # testing `if userEntry.type == "regular"`
              null;

          mkUsers =
            userEntries:
            let
              users = lib.mapAttrs getEntryPath userEntries;
            in
            lib.filterAttrs (_name: value: value != null) users;
        in
        importDir (src + "/users") mkUsers;

      # Attribute set mapping hostname (defined in hosts/) to a set of home
      # configurations (modules) for that host. If a host has no home
      # configuration, it will be omitted from the set. Likewise, if the user
      # directory does not contain a home-configuration.nix file, it will
      # be silently omitted - not defining a configuration is not an error.
      homesNested =
        let
          getEntryPath =
            _username: userEntry:
            if userEntry.type == "regular" then
              userEntry.path
            else if builtins.pathExists (userEntry.path + "/home-configuration.nix") then
              userEntry.path + "/home-configuration.nix"
            else
              null;

          # Returns an attrset mapping username to home configuration path. It may be empty
          # if no users have a home configuration.
          mkHostUsers =
            userEntries:
            let
              hostUsers = lib.mapAttrs getEntryPath userEntries;
            in
            lib.filterAttrs (_name: value: value != null) hostUsers;

          mkHosts =
            hostEntries:
            let
              hostDirs = lib.filterAttrs (_: entry: entry.type == "directory") hostEntries;
              hostToUsers = _hostname: entry: importDir (entry.path + "/users") mkHostUsers;
              hosts = lib.mapAttrs hostToUsers hostDirs;
            in
            lib.filterAttrs (_hostname: users: users != { }) hosts;
        in
        importDir (src + "/hosts") mkHosts;

      # Attrset of ${system}.homeConfigurations."${username}@${hostname}"
      standaloneHomeConfigurations =
        let
          mkHomeConfiguration =
            {
              username,
              modulePath,
              pkgs,
            }:
            home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              extraSpecialArgs = specialArgs;
              modules = [
                perSystemModule
                modulePath
                (
                  { config, ... }:
                  {
                    home.username = lib.mkDefault username;
                    # Home Manager would use builtins.getEnv prior to 20.09, but
                    # this feature was removed to make it pure. However, since
                    # we know the operating system and username ahead of time,
                    # it's safe enough to automatically set a default for the home
                    # directory and let users customize it if they want. This is
                    # done automatically in the NixOS or nix-darwin modules too.
                    home.homeDirectory =
                      let
                        username = config.home.username;
                        homeDir = if pkgs.stdenv.isDarwin then "/Users/${username}" else "/home/${username}";
                      in
                      lib.mkDefault homeDir;
                  }
                )
              ];
            };

          homesFlat = lib.concatMapAttrs (
            hostname: hostUserModules:
            lib.mapAttrs' (username: modulePath: {
              name = "${username}@${hostname}";
              value = {
                inherit hostname username modulePath;
              };
            }) hostUserModules
          ) homesNested;
        in
        eachSystem (
          { pkgs, ... }:
          {
            homeConfigurations = lib.mapAttrs (
              _name: homeData:
              mkHomeConfiguration {
                inherit (homeData) modulePath username;
                  inherit pkgs;
                }
              ) homesFlat
              // lib.mapAttrs (
                username: modulePath: mkHomeConfiguration { inherit pkgs username modulePath; }
              ) homesGeneric;
          }
        );

      hosts = importDir (src + "/hosts") (
        entries:
        let
          loadDefaultFn = { class, value }@inputs: inputs;

          loadDefault = path: loadDefaultFn (import path { inherit flake inputs; });


          loadNixOS = hostname: path: {
            class = "nixos";
            value = inputs.nixpkgs.lib.nixosSystem {
              modules = [
                nixpkgsConfigModule
                perSystemModule
                path
              ] ++ mkHomeUsersModule hostname home-manager.nixosModules.default;
              inherit specialArgs;
            };
          };

          loadNixOSRPi =
            hostname: path:
            let
              nixos-raspberrypi =
                inputs.nixos-raspberrypi
                  or (throw ''${path} depends on nixos-raspberrypi. To fix this, add `inputs.nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi";` to your flake'');
            in
            {
              class = "nixos-raspberrypi";
              value = nixos-raspberrypi.lib.nixosSystem {
                modules = [
                  nixpkgsConfigModule
                  perSystemModule
                  path
                 ] ++ mkHomeUsersModule hostname home-manager.nixosModules.default;
              inherit specialArgs;
            };
          };

          loadNixDarwin =
            hostname: path:
            let
              nix-darwin =
                inputs.nix-darwin
                  or (throw ''${path} depends on nix-darwin. To fix this, add `inputs.nix-darwin.url = "github:Lnl7/nix-darwin";` to your flake'');
            in
            {
              class = "nix-darwin";
              value = nix-darwin.lib.darwinSystem {
                modules = [
                  nixpkgsConfigModule
                  perSystemModule
                  path
                ] ++ mkHomeUsersModule hostname home-manager.darwinModules.default;
                inherit specialArgs;
              };
            };

          loadSystemManager =
            hostname: path:
            let
              system-manager =
                inputs.system-manager
                  or (throw ''${path} depends on system-manager. To fix this, add `inputs.system-manager.url = "github:numtide/system-manager"; to your flake'');
            in
            {
              class = "system-manager";
              value = system-manager.lib.makeSystemConfig {
                modules = [
                  perSystemModule
                  path
                ];
                extraSpecialArgs = specialArgs // {
                  inherit hostname;
                };
              };
            };

          loadHost =
            name:
            { path, type }:
            if builtins.pathExists (path + "/default.nix") then
              loadDefault  (path + "/default.nix")
            else if builtins.pathExists (path + "/configuration.nix") then
              loadNixOS name (path + "/configuration.nix")
            else if builtins.pathExists (path + "/rpi-configuration.nix") then
              loadNixOSRPi name (path + "/rpi-configuration.nix")
            else if builtins.pathExists (path + "/darwin-configuration.nix") then
              loadNixDarwin name (path + "/darwin-configuration.nix")
            else if builtins.pathExists (path + "/system-configuration.nix") then
              loadSystemManager name (path + "/system-configuration.nix")
            else if builtins.hasAttr name homesNested then
              # If there are any home configurations defined for this host, they
              # must be standalone configurations since there is no OS config.
              # No config should be returned, but no error should be thrown either.
              null
            else
              throw "host '${name}' does not have a configuration";

          hostsOrNull = lib.mapAttrs loadHost entries;
        in
        lib.filterAttrs (_n: v: v != null) hostsOrNull
      );

      hostsByCategory = lib.mapAttrs (_: hosts: lib.listToAttrs hosts) (
        lib.groupBy (
          x:
          if x.value.class == "nixos" then
            "nixosConfigurations"
          else if x.value.class == "nix-darwin" then
            "darwinConfigurations"
          else if x.value.class == "system-manager" then
            "systemConfigs"
          else if x.value.class == "robotnix" then
            "robotnixConfigurations"
          else if x.value.class == "nix-on-droid" then
            "nixOnDroidConfigurations"
          else
            throw "host '${x.name}' of class '${x.value.class or "unknown"}' not supported"
        ) (lib.attrsToList hosts)
      );

      publisherArgs = {
        inherit flake inputs;
      };

      expectsPublisherArgs =
        module:
        builtins.isFunction module
        && builtins.all (arg: builtins.elem arg (builtins.attrNames publisherArgs)) (
          builtins.attrNames (builtins.functionArgs module)
        );

      # Checks if the given module is wrapped in a function accepting one or more of publisherArgs.
      # If so, call that function. This allows modules to refer to the flake where it is
      # defined, while the module arguments "flake", "inputs" and "perSystem" refer to the flake
      # where the module is consumed.
      injectPublisherArgs =
        modulePath:
        let
          module = import modulePath;
        in
        if expectsPublisherArgs module then
          lib.setDefaultModuleLocation modulePath (module publisherArgs)
        else
          modulePath;

      modules =
        let
          path = src + "/modules";
          moduleDirs = builtins.attrNames (
            lib.filterAttrs (_name: value: value == "directory") (builtins.readDir path)
          );
        in
        lib.optionalAttrs (builtins.pathExists path) (
          lib.genAttrs moduleDirs (
            name:
            lib.mapAttrs (_name: moduleDir: injectPublisherArgs moduleDir) (
              importDir (path + "/${name}") entriesPath
            )
          )
        );

      # See the comment in mkEachSystem
      unfilteredPackages =
        lib.traceIf (builtins.pathExists (src + "/pkgs")) "blueprint: the /pkgs folder is now /packages"
          (
            let
              entries =
                (optionalPathAttrs (src + "/packages") (path: importDir path lib.id))
                // (optionalPathAttrs (src + "/package.nix") (path: {
                  default = {
                    inherit path;
                  };
                }))
                // (optionalPathAttrs (src + "/formatter.nix") (path: {
                  formatter = {
                    inherit path;
                  };
                }));
            in
            eachSystem (
              { newScope, system, ... }:
              lib.mapAttrs (pname: { path, ... }: newScope { inherit pname; } path { }) entries
            )
          );
    in
    # FIXME: maybe there are two layers to this. The blueprint, and then the mapping to flake outputs.
    {
      formatter = eachSystem (
        { pkgs, perSystem, ... }:
        perSystem.self.formatter or pkgs.nixfmt-tree
      );

      lib = tryImport (src + "/lib") specialArgs;

      # expose the functor to the top-level
      # FIXME: only if it exists
      __functor = x: inputs.self.lib.__functor x;

      devShells =
        let
          namedNix = (
            optionalPathAttrs (src + "/devshells") (
              path:
              (importDir path (
                entries:
                eachSystem (
                  { newScope, ... }:
                  lib.mapAttrs (pname: { path, type }: newScope { inherit pname; } path { }) (
                    lib.filterAttrs (
                      _name:
                      { path, type }:
                      type == "regular" || (type == "directory" && lib.pathExists "${path}/default.nix")
                    ) entries
                  )
                )
              ))
            )
          );

          namedToml = (
            optionalPathAttrs (src + "/devshells") (
              path:
              (importTomlFilesAt path (
                entries:
                eachSystem (
                  { newScope, perSystem, ... }:
                  lib.mapAttrs (
                    pname: { path, type }: newScope { inherit pname; } (_: devshellFromTOML perSystem path) { }
                  ) entries
                )
              ))
            )
          );

          defaultNix = (
            optionalPathAttrs (src + "/devshell.nix") (
              path:
              eachSystem (
                { newScope, ... }:
                {
                  default = newScope { pname = "default"; } path { };
                }
              )
            )
          );

          defaultToml = (
            optionalPathAttrs (src + "/devshell.toml") (
              path:
              eachSystem (
                { newScope, perSystem, ... }:
                {
                  default = newScope { pname = "default"; } (_: devshellFromTOML perSystem path) { };
                }
              )
            )
          );

          merge =
            prev: item:
            let
              systems = lib.attrNames (prev // item);
              mergeSystem = system: { ${system} = (prev.${system} or { }) // (item.${system} or { }); };
              mergedSystems = builtins.map mergeSystem systems;
            in
            lib.mergeAttrsList mergedSystems;
        in
        lib.foldl merge { } [
          namedToml
          namedNix
          defaultToml
          defaultNix
        ];

      # See the comment in mkEachSystem
      packages = lib.mapAttrs filterPlatforms unfilteredPackages;

      # Defining homeConfigurations under legacyPackages allows the home-manager CLI
      # to automatically detect the right output for the current system without
      # either manually defining the pkgs set (requires explicit system) or breaking
      # nix3 CLI output (`packages` output expects flat attrset)
      # FIXME: Find another way to make this work without introducing legacyPackages.
      #        May involve changing upstream home-manager.
      legacyPackages = standaloneHomeConfigurations;

      darwinConfigurations = lib.mapAttrs (_: x: x.value) (hostsByCategory.darwinConfigurations or { });
      nixosConfigurations = lib.mapAttrs (_: x: x.value) (hostsByCategory.nixosConfigurations or { });
      systemConfigs = lib.mapAttrs (_: x: x.value) (hostsByCategory.systemConfigs or { });
      robotnixConfigurations = lib.mapAttrs (_: x: x.value) (hostsByCategory.robotnixConfigurations or { });
      nixOnDroidConfigurations = lib.mapAttrs (_: x: x.value) (hostsByCategory.nixOnDroidConfigurations or { });

      inherit modules;

      darwinModules = modules.darwin or { };
      homeModules = modules.home or { };
      # TODO: how to extract NixOS tests?
      nixosModules = modules.nixos or { };

      templates = importDir (src + "/templates") (
        entries:
        lib.mapAttrs (
          name:
          { path, type }:
          {
            path = path;
            description =
              if builtins.pathExists (path + "/flake.nix") then
                (import (path + "/flake.nix")).description or name
              else
                name;
          }
        ) entries
      );

      checks = eachSystem (
        { system, pkgs, ... }:
        lib.mergeAttrsList (
          [
            # add all the supported packages, and their passthru.tests to checks
            (withPrefix "pkgs-" (
              lib.concatMapAttrs (
                pname: package:
                {
                  ${pname} = package;
                }
                # also add the passthru.tests to the checks
                // (lib.mapAttrs' (tname: test: {
                  name = "${pname}-${tname}";
                  value = test;
                }) (filterPlatforms system (package.passthru.tests or { })))
              ) (filterPlatforms system (inputs.self.packages.${system} or { }))
            ))
            # build all the devshells
            (withPrefix "devshell-" (inputs.self.devShells.${system} or { }))
            # add nixos system closures to checks
            (withPrefix "nixos-" (
              lib.mapAttrs (_: x: x.config.system.build.toplevel) (
                lib.filterAttrs (_: x: x.pkgs.stdenv.hostPlatform.system == system) (inputs.self.nixosConfigurations or { })
              )
            ))
            # add darwin system closures to checks
            (withPrefix "darwin-" (
              lib.mapAttrs (_: x: x.system) (
                lib.filterAttrs (_: x: x.pkgs.stdenv.hostPlatform.system == system) (inputs.self.darwinConfigurations or { })
              )
            ))
            # add system-manager closures to checks
            (withPrefix "system-" (
              lib.mapAttrs (_: x: x) (
                lib.filterAttrs (_: x: x.system == system) (inputs.self.systemConfigs or { })
              )
            ))
            # load checks from the /checks folder. Those take precedence over the others.
            (filterPlatforms system (
              optionalPathAttrs (src + "/checks") (
                path:
                let
                  importChecksFn = lib.mapAttrs (
                    pname: { type, path }: import path {
                      inherit
                        pname
                        flake
                        inputs
                        system
                        pkgs
                        ;
                    }
                  );
                in

                (importDir path importChecksFn)
              )
            ))
          ]
          ++ (lib.optional (inputs.self.lib.tests or { } != { }) {
            lib-tests = pkgs.runCommandLocal "lib-tests" { nativeBuildInputs = [ pkgs.nix-unit ]; } ''
              export HOME="$(realpath .)"
              export NIX_CONFIG='
              extra-experimental-features = nix-command flakes
              flake-registry = ""
              '

              nix-unit --flake ${flake}#lib.tests ${
                toString (
                  lib.mapAttrsToList (k: v: "--override-input ${k} ${v}") (builtins.removeAttrs inputs [ "self" ])
                )
              }

              touch $out
            '';
          })
        )
      );
    };

  # Create a new flake blueprint
  mkBlueprint =
    {
      # Pass the flake inputs to blueprint
      inputs,
      # Load the blueprint from this path
      prefix ? null,
      # Used to configure nixpkgs
      nixpkgs ? {
        config = { };
      },
      # The systems to generate the flake for
      systems ? inputs.systems or bpInputs.systems,
    }:
    mkBlueprint' {
      inputs = bpInputs // inputs;
      flake = inputs.self;

      inherit nixpkgs;

      src =
        if prefix == null then
          inputs.self
        else if builtins.isPath prefix then
          prefix
        else if builtins.isString prefix then
          "${inputs.self}/${prefix}"
        else
          throw "${builtins.typeOf prefix} is not supported for the prefix";

      # Make compatible with github:nix-systems/default
      systems = if lib.isList systems then systems else import systems;
    };

  tests = {
    # Basic sanity test
    testPass = {
      expr = 1;
      expected = 1;
    };

    # Tests for filterPlatforms function
    testFilterPlatformsEmptyMetaPlatforms = {
      expr = filterPlatforms "x86_64-linux" {
        foo = { meta.platforms = [ ]; };
      };
      expected = {
        foo = { meta.platforms = [ ]; };
      };
    };

    testFilterPlatformsNoMetaPlatforms = {
      expr = filterPlatforms "x86_64-linux" {
        foo = { };
      };
      expected = {
        foo = { };
      };
    };

    testFilterPlatformsMatchingPlatform = {
      expr = filterPlatforms "x86_64-linux" {
        foo = { meta.platforms = [ "x86_64-linux" "aarch64-linux" ]; };
      };
      expected = {
        foo = { meta.platforms = [ "x86_64-linux" "aarch64-linux" ]; };
      };
    };

    testFilterPlatformsNonMatchingPlatform = {
      expr = filterPlatforms "x86_64-linux" {
        foo = { meta.platforms = [ "aarch64-darwin" "x86_64-darwin" ]; };
      };
      expected = { };
    };

    testFilterPlatformsMixedPackages = {
      expr = filterPlatforms "x86_64-linux" {
        pkgAll = { };
        pkgLinux = { meta.platforms = [ "x86_64-linux" ]; };
        pkgDarwin = { meta.platforms = [ "x86_64-darwin" ]; };
        pkgEmpty = { meta.platforms = [ ]; };
      };
      expected = {
        pkgAll = { };
        pkgLinux = { meta.platforms = [ "x86_64-linux" ]; };
        pkgEmpty = { meta.platforms = [ ]; };
      };
    };

    # Tests for withPrefix function
    testWithPrefixEmpty = {
      expr = withPrefix "test-" { };
      expected = { };
    };

    testWithPrefixSingle = {
      expr = withPrefix "pkg-" { foo = "bar"; };
      expected = { "pkg-foo" = "bar"; };
    };

    testWithPrefixMultiple = {
      expr = withPrefix "check-" {
        foo = "bar";
        baz = "qux";
        test = 123;
      };
      expected = {
        "check-foo" = "bar";
        "check-baz" = "qux";
        "check-test" = 123;
      };
    };

    testWithPrefixEmptyPrefix = {
      expr = withPrefix "" {
        foo = "bar";
        baz = "qux";
      };
      expected = {
        foo = "bar";
        baz = "qux";
      };
    };

    testWithPrefixComplexValues = {
      expr = withPrefix "devshell-" {
        default = { a = 1; b = 2; };
        custom = [ 1 2 3 ];
      };
      expected = {
        "devshell-default" = { a = 1; b = 2; };
        "devshell-custom" = [ 1 2 3 ];
      };
    };

    # Tests for entriesPath function
    testEntriesPathEmpty = {
      expr = entriesPath { };
      expected = { };
    };

    testEntriesPathSingle = {
      expr = entriesPath {
        foo = { path = /test/foo; type = "regular"; };
      };
      expected = {
        foo = /test/foo;
      };
    };

    testEntriesPathMultiple = {
      expr = entriesPath {
        foo = { path = /test/foo; type = "regular"; };
        bar = { path = /test/bar; type = "directory"; };
        baz = { path = /test/baz.nix; type = "regular"; };
      };
      expected = {
        foo = /test/foo;
        bar = /test/bar;
        baz = /test/baz.nix;
      };
    };

    # Tests for optionalPathAttrs function
    testOptionalPathAttrsNonExistent = {
      expr = optionalPathAttrs /nonexistent/path/that/does/not/exist (path: { found = true; });
      expected = { };
    };

    testOptionalPathAttrsExistent = {
      expr = optionalPathAttrs ./. (path: { found = true; inherit path; });
      expected = { found = true; path = ./.; };
    };

    # Tests for tryImport function
    testTryImportNonExistent = {
      expr = tryImport /nonexistent/path/that/does/not/exist { };
      expected = { };
    };

    testTryImportExistent = {
      expr = tryImport ./default.nix { inherit inputs; };
      expected = rec {
        inherit
          mkEachSystem
          optionalPathAttrs
          tryImport
          importTomlFilesAt
          importDir
          entriesPath
          withPrefix
          filterPlatforms
          mkBlueprint'
          mkBlueprint
          tests
          __functor
          ;
      };
    };

    # Tests for importDir with mock filesystem paths
    # Note: These tests verify the structure, actual file reading would require real files
    testImportDirEmpty = {
      expr = importDir /nonexistent/empty/path (entries: entries);
      expected = { };
    };

    # Tests for importTomlFilesAt with mock filesystem paths
    testImportTomlFilesAtEmpty = {
      expr = importTomlFilesAt /nonexistent/empty/path (entries: entries);
      expected = { };
    };

    # Test that mkBlueprint is a functor
    testFunctorExists = {
      expr = lib.isFunction __functor;
      expected = true;
    };

    # Test that mkBlueprint is callable
    testMkBlueprintIsFunction = {
      expr = lib.isFunction mkBlueprint;
      expected = true;
    };

    # Tests for mkEachSystem basic structure
    testMkEachSystemSingleSystem = {
      expr =
        let
          result = mkEachSystem {
            inputs = { nixpkgs = inputs.nixpkgs; self = { }; _ = { }; };
            flake = { };
            systems = [ "x86_64-linux" ];
            nixpkgs = { };
            unfilteredPackages = { "x86_64-linux" = { }; };
          };
        in
        {
          hasEachSystem = lib.isFunction result.eachSystem;
          hasSystemArgs = lib.isAttrs result.systemArgs;
          systemCount = lib.length (lib.attrNames result.systemArgs);
        };
      expected = {
        hasEachSystem = true;
        hasSystemArgs = true;
        systemCount = 1;
      };
    };

    testMkEachSystemMultipleSystems = {
      expr =
        let
          result = mkEachSystem {
            inputs = { nixpkgs = inputs.nixpkgs; self = { }; _ = { }; };
            flake = { };
            systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" ];
            nixpkgs = { };
            unfilteredPackages = {
              "x86_64-linux" = { };
              "aarch64-linux" = { };
              "x86_64-darwin" = { };
            };
          };
        in
        {
          hasEachSystem = lib.isFunction result.eachSystem;
          hasSystemArgs = lib.isAttrs result.systemArgs;
          systemCount = lib.length (lib.attrNames result.systemArgs);
          hasx86_64Linux = lib.hasAttr "x86_64-linux" result.systemArgs;
          hasaarch64Linux = lib.hasAttr "aarch64-linux" result.systemArgs;
          hasx86_64Darwin = lib.hasAttr "x86_64-darwin" result.systemArgs;
        };
      expected = {
        hasEachSystem = true;
        hasSystemArgs = true;
        systemCount = 3;
        hasx86_64Linux = true;
        hasaarch64Linux = true;
        hasx86_64Darwin = true;
      };
    };

    testMkEachSystemEachSystemFunction = {
      expr =
        let
          result = mkEachSystem {
            inputs = { nixpkgs = inputs.nixpkgs; self = { }; _ = { }; };
            flake = { };
            systems = [ "x86_64-linux" "aarch64-linux" ];
            nixpkgs = { };
            unfilteredPackages = {
              "x86_64-linux" = { };
              "aarch64-linux" = { };
            };
          };
          eachSystemResult = result.eachSystem (scope: { test = scope.system; });
        in
        {
          isAttrs = lib.isAttrs eachSystemResult;
          hasLinux = lib.hasAttr "x86_64-linux" eachSystemResult;
          hasAarch64 = lib.hasAttr "aarch64-linux" eachSystemResult;
          linuxValue = eachSystemResult."x86_64-linux".test or null;
          aarch64Value = eachSystemResult."aarch64-linux".test or null;
        };
      expected = {
        isAttrs = true;
        hasLinux = true;
        hasAarch64 = true;
        linuxValue = "x86_64-linux";
        aarch64Value = "aarch64-linux";
      };
    };

    # Tests for importDir with real filesystem
    testImportDirRealFiles = {
      expr =
        let
          result = importDir ./test-fixtures/nix-files (entries: lib.attrNames entries);
        in
        {
          hasFiles = lib.length result > 0;
          hasFoo = lib.elem "foo" result;
          hasBar = lib.elem "bar" result;
          hasSubdir = lib.elem "subdir" result;
          hasIgnoredTxt = lib.elem "ignored" result;
        };
      expected = {
        hasFiles = true;
        hasFoo = true;
        hasBar = true;
        hasSubdir = true;
        hasIgnoredTxt = false;  # .txt files should be ignored
      };
    };

    testImportDirWithPaths = {
      expr =
        let
          result = importDir ./test-fixtures/nix-files entriesPath;
        in
        {
          hasFoo = lib.hasAttr "foo" result;
          hasBar = lib.hasAttr "bar" result;
          hasSubdir = lib.hasAttr "subdir" result;
          fooIsPath = lib.isPath result.foo or false;
          subdirIsPath = lib.isPath result.subdir or false;
        };
      expected = {
        hasFoo = true;
        hasBar = true;
        hasSubdir = true;
        fooIsPath = true;
        subdirIsPath = true;
      };
    };

    testImportDirPrecedence = {
      expr =
        let
          # If both foo.nix and foo/ exist, foo.nix should take precedence
          result = importDir ./test-fixtures/nix-files (
            entries:
            lib.mapAttrs (_name: { type, ... }: type) entries
          );
        in
        {
          fooType = result.foo or null;
          barType = result.bar or null;
          subdirType = result.subdir or null;
        };
      expected = {
        fooType = "regular";
        barType = "regular";
        subdirType = "directory";
      };
    };

    # Tests for importTomlFilesAt with real filesystem
    testImportTomlFilesAtRealFiles = {
      expr =
        let
          result = importTomlFilesAt ./test-fixtures/toml-files (entries: lib.attrNames entries);
        in
        {
          hasFiles = lib.length result > 0;
          hasDevshell = lib.elem "devshell" result;
          hasOther = lib.elem "other" result;
          count = lib.length result;
        };
      expected = {
        hasFiles = true;
        hasDevshell = true;
        hasOther = true;
        count = 2;
      };
    };

    testImportTomlFilesAtWithPaths = {
      expr =
        let
          result = importTomlFilesAt ./test-fixtures/toml-files entriesPath;
        in
        {
          hasDevshell = lib.hasAttr "devshell" result;
          hasOther = lib.hasAttr "other" result;
          devshellIsPath = lib.isPath result.devshell or false;
          otherIsPath = lib.isPath result.other or false;
        };
      expected = {
        hasDevshell = true;
        hasOther = true;
        devshellIsPath = true;
        otherIsPath = true;
      };
    };
  };

  # Make this callable
  __functor = _: mkBlueprint;
}

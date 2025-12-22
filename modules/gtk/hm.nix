{
  mkTarget,
  pkgs,
  config,
  lib,
  options,
  ...
}:
mkTarget {
  options = {
    flatpakSupport.enable = config.lib.stylix.mkEnableTarget "support for theming Flatpak apps" true;
  };

  imports = lib.singleton (
    lib.mkRemovedOptionModule [
      "stylix"
      "targets"
      "gtk"
      "extraCss"
    ] "Use `gtk.gtk3.extraCss` and/or `gtk.gtk4.extraCss` instead."
  );

  config = [
    {
      # programs.dconf.enable = true; required in system config
      gtk.enable = true;
    }
    (
      { fonts }:
      {
        gtk.font = {
          inherit (fonts.sansSerif) package name;
          size = fonts.sizes.applications;
        };
      }
    )
    (
      { cfg, colors }:
      let
        baseCss = colors {
          template = ./gtk.css.mustache;
          extension = ".css";
        };

        finalGtk3Css = pkgs.runCommandLocal "stylix-gtk3.css" { } ''
          cat ${baseCss} >>$out
          echo ${lib.escapeShellArg config.gtk.gtk3.extraCss} >>$out
        '';

        finalGtk4Css = pkgs.runCommandLocal "stylix-gtk4.css" { } ''
          cat ${baseCss} >>$out
          echo ${lib.escapeShellArg config.gtk.gtk4.extraCss} >>$out
        '';
      in
      lib.mkMerge [
        {
          gtk.theme = {
            package = pkgs.adw-gtk3;
            name = "adw-gtk3";
          };
          gtk.gtk4.theme = config.gtk.theme;

          xdg.configFile = {
            "gtk-3.0/gtk.css".source = finalGtk3Css;
            "gtk-4.0/gtk.css".source = finalGtk4Css;
          };
        }
        (lib.mkIf cfg.flatpakSupport.enable (
          lib.mkMerge [
            {
              # Flatpak apps apparently don't consume the CSS config. This workaround appends it to the theme directly.
              home.file.".themes/${config.gtk.theme.name}".source =
                pkgs.stdenvNoCC.mkDerivation
                  {
                    name = "flattenedGtkTheme";
                    src = "${config.gtk.theme.package}/share/themes/${config.gtk.theme.name}";

                    installPhase = ''
                      cp --recursive . $out
                      cat ${finalGtk3Css} >> $out/gtk-3.0/gtk.css
                      cat ${finalGtk4Css} >> $out/gtk-4.0/gtk.css
                    '';
                  };
            }
            (
              let
                filesystem = "${config.home.homeDirectory}/.themes/${config.gtk.theme.name}:ro";
                theme = config.gtk.theme.name;
              in
              if options ? services.flatpak.overrides then
                {
                  # Let Flatpak apps read the theme and force them to use it.
                  # This requires nix-flatpak to be imported externally.
                  services.flatpak.overrides.global = {
                    Context.filesystems = [ filesystem ];
                    Environment.GTK_THEME = theme;
                  };
                }
              else
                {
                  # This is likely incompatible with other modules that write to this file.
                  xdg.dataFile."flatpak/overrides/global".text = ''
                    [Context]
                    filesystems=${filesystem}

                    [Environment]
                    GTK_THEME=${theme}
                  '';
                }
            )
          ]
        ))
      ]
    )
  ];
}

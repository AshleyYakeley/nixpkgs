/*

Configuration files are linked to /etc/fonts/conf.d/

This module generates a package containing configuration files and link it in /etc/fonts.

Fontconfig reads files in folder name / file name order, so the number prepended to the configuration file name decide the order of parsing.
Low number means high priority.

*/

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.fonts.fontconfig;

  fcBool = x: "<bool>" + (boolToString x) + "</bool>";
  pkg = pkgs.fontconfig;

  # configuration file to read fontconfig cache
  # priority 0
  cacheConf  = makeCacheConf {};

  # generate the font cache setting file
  # When cross-compiling, we can’t generate the cache, so we skip the
  # <cachedir> part. fontconfig still works but is a little slower in
  # looking things up.
  makeCacheConf = { }:
    let
      makeCache = fontconfig: pkgs.makeFontsCache { inherit fontconfig; fontDirectories = config.fonts.fonts; };
      cache     = makeCache pkgs.fontconfig;
      cache32   = makeCache pkgs.pkgsi686Linux.fontconfig;
    in
    pkgs.writeText "fc-00-nixos-cache.conf" ''
      <?xml version='1.0'?>
      <!DOCTYPE fontconfig SYSTEM 'urn:fontconfig:fonts.dtd'>
      <fontconfig>
        <!-- Font directories -->
        ${concatStringsSep "\n" (map (font: "<dir>${font}</dir>") config.fonts.fonts)}
        ${optionalString (pkgs.stdenv.hostPlatform == pkgs.stdenv.buildPlatform) ''
        <!-- Pre-generated font caches -->
        <cachedir>${cache}</cachedir>
        ${optionalString (pkgs.stdenv.isx86_64 && cfg.cache32Bit) ''
          <cachedir>${cache32}</cachedir>
        ''}
        ''}
      </fontconfig>
    '';

  # rendering settings configuration file
  # priority 10
  renderConf = pkgs.writeText "fc-10-nixos-rendering.conf" ''
    <?xml version='1.0'?>
    <!DOCTYPE fontconfig SYSTEM 'urn:fontconfig:fonts.dtd'>
    <fontconfig>

      <!-- Default rendering settings -->
      <match target="pattern">
        <edit mode="append" name="hinting">
          ${fcBool cfg.hinting.enable}
        </edit>
        <edit mode="append" name="autohint">
          ${fcBool cfg.hinting.autohint}
        </edit>
        <edit mode="append" name="hintstyle">
          <const>hintslight</const>
        </edit>
        <edit mode="append" name="antialias">
          ${fcBool cfg.antialias}
        </edit>
        <edit mode="append" name="rgba">
          <const>${cfg.subpixel.rgba}</const>
        </edit>
        <edit mode="append" name="lcdfilter">
          <const>lcd${cfg.subpixel.lcdfilter}</const>
        </edit>
      </match>

      ${optionalString (cfg.dpi != 0) ''
      <match target="pattern">
        <edit name="dpi" mode="assign">
          <double>${toString cfg.dpi}</double>
        </edit>
      </match>
      ''}

    </fontconfig>
  '';

  # local configuration file
  localConf = pkgs.writeText "fc-local.conf" cfg.localConf;

  # default fonts configuration file
  # priority 52
  defaultFontsConf =
    let genDefault = fonts: name:
      optionalString (fonts != []) ''
        <alias binding="same">
          <family>${name}</family>
          <prefer>
          ${concatStringsSep ""
          (map (font: ''
            <family>${font}</family>
          '') fonts)}
          </prefer>
        </alias>
      '';
    in
    pkgs.writeText "fc-52-nixos-default-fonts.conf" ''
    <?xml version='1.0'?>
    <!DOCTYPE fontconfig SYSTEM 'urn:fontconfig:fonts.dtd'>
    <fontconfig>

      <!-- Default fonts -->
      ${genDefault cfg.defaultFonts.sansSerif "sans-serif"}

      ${genDefault cfg.defaultFonts.serif     "serif"}

      ${genDefault cfg.defaultFonts.monospace "monospace"}

      ${genDefault cfg.defaultFonts.emoji "emoji"}

    </fontconfig>
  '';

  # bitmap font options
  # priority 53
  rejectBitmaps = pkgs.writeText "fc-53-no-bitmaps.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>

    ${optionalString (!cfg.allowBitmaps) ''
    <!-- Reject bitmap fonts -->
    <selectfont>
      <rejectfont>
        <pattern>
          <patelt name="scalable"><bool>false</bool></patelt>
        </pattern>
      </rejectfont>
    </selectfont>
    ''}

    <!-- Use embedded bitmaps in fonts like Calibri? -->
    <match target="font">
      <edit name="embeddedbitmap" mode="assign">
        ${fcBool cfg.useEmbeddedBitmaps}
      </edit>
    </match>

    </fontconfig>
  '';

  # reject Type 1 fonts
  # priority 53
  rejectType1 = pkgs.writeText "fc-53-nixos-reject-type1.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>

    <!-- Reject Type 1 fonts -->
    <selectfont>
      <rejectfont>
        <pattern>
          <patelt name="fontformat"><string>Type 1</string></patelt>
        </pattern>
      </rejectfont>
    </selectfont>

    </fontconfig>
  '';

  # fontconfig configuration package
  confPkg = pkgs.runCommand "fontconfig-conf" {
    preferLocalBuild = true;
  } ''
    dst=$out/etc/fonts/conf.d
    mkdir -p $dst

    # fonts.conf
    ln -s ${pkg.out}/etc/fonts/fonts.conf \
          $dst/../fonts.conf
    # TODO: remove this legacy symlink once people stop using packages built before #95358 was merged
    mkdir -p $out/etc/fonts/2.11
    ln -s /etc/fonts/fonts.conf \
          $out/etc/fonts/2.11/fonts.conf

    # fontconfig default config files
    ln -s ${pkg.out}/etc/fonts/conf.d/*.conf \
          $dst/

    # 00-nixos-cache.conf
    ln -s ${cacheConf}  $dst/00-nixos-cache.conf

    # 10-nixos-rendering.conf
    ln -s ${renderConf}       $dst/10-nixos-rendering.conf

    # 50-user.conf
    # Since latest fontconfig looks for default files inside the package,
    # we had to move this one elsewhere to be able to exclude it here.
    ${optionalString cfg.includeUserConf ''
    ln -s ${pkg.out}/etc/fonts/conf.d.bak/50-user.conf $dst/50-user.conf
    ''}

    # local.conf (indirect priority 51)
    ${optionalString (cfg.localConf != "") ''
    ln -s ${localConf}        $dst/../local.conf
    ''}

    # 52-nixos-default-fonts.conf
    ln -s ${defaultFontsConf} $dst/52-nixos-default-fonts.conf

    # 53-no-bitmaps.conf
    ln -s ${rejectBitmaps} $dst/53-no-bitmaps.conf

    ${optionalString (!cfg.allowType1) ''
    # 53-nixos-reject-type1.conf
    ln -s ${rejectType1} $dst/53-nixos-reject-type1.conf
    ''}
  '';

  # Package with configuration files
  # this merge all the packages in the fonts.fontconfig.confPackages list
  fontconfigEtc = pkgs.buildEnv {
    name  = "fontconfig-etc";
    paths = cfg.confPackages;
    ignoreCollisions = true;
  };
in
{
  imports = [
    (mkRenamedOptionModule [ "fonts" "fontconfig" "ultimate" "allowBitmaps" ] [ "fonts" "fontconfig" "allowBitmaps" ])
    (mkRenamedOptionModule [ "fonts" "fontconfig" "ultimate" "allowType1" ] [ "fonts" "fontconfig" "allowType1" ])
    (mkRenamedOptionModule [ "fonts" "fontconfig" "ultimate" "useEmbeddedBitmaps" ] [ "fonts" "fontconfig" "useEmbeddedBitmaps" ])
    (mkRenamedOptionModule [ "fonts" "fontconfig" "ultimate" "forceAutohint" ] [ "fonts" "fontconfig" "forceAutohint" ])
    (mkRenamedOptionModule [ "fonts" "fontconfig" "ultimate" "renderMonoTTFAsBitmap" ] [ "fonts" "fontconfig" "renderMonoTTFAsBitmap" ])
    (mkRemovedOptionModule [ "fonts" "fontconfig" "hinting" "style" ] "")
    (mkRemovedOptionModule [ "fonts" "fontconfig" "forceAutohint" ] "")
    (mkRemovedOptionModule [ "fonts" "fontconfig" "renderMonoTTFAsBitmap" ] "")
  ] ++ lib.forEach [ "enable" "substitutions" "preset" ]
     (opt: lib.mkRemovedOptionModule [ "fonts" "fontconfig" "ultimate" "${opt}" ] ''
       The fonts.fontconfig.ultimate module and configuration is obsolete.
       The repository has since been archived and activity has ceased.
       https://github.com/bohoomil/fontconfig-ultimate/issues/171.
       No action should be needed for font configuration, as the fonts.fontconfig
       module is already used by default.
     '');

  options = {

    fonts = {

      fontconfig = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = ''
            If enabled, a Fontconfig configuration file will be built
            pointing to a set of default fonts.  If you don't care about
            running X11 applications or any other program that uses
            Fontconfig, you can turn this option off and prevent a
            dependency on all those fonts.
          '';
        };

        confPackages = mkOption {
          internal = true;
          type     = with types; listOf path;
          default  = [ ];
          description = ''
            Fontconfig configuration packages.
          '';
        };

        antialias = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Enable font antialiasing. At high resolution (> 200 DPI),
            antialiasing has no visible effect; users of such displays may want
            to disable this option.
          '';
        };

        dpi = mkOption {
          type = types.int;
          default = 0;
          description = ''
            Force DPI setting. Setting to <literal>0</literal> disables DPI
            forcing; the DPI detected for the display will be used.
          '';
        };

        localConf = mkOption {
          type = types.lines;
          default = "";
          description = ''
            System-wide customization file contents, has higher priority than
            <literal>defaultFonts</literal> settings.
          '';
        };

        defaultFonts = {
          monospace = mkOption {
            type = types.listOf types.str;
            default = ["DejaVu Sans Mono"];
            description = ''
              System-wide default monospace font(s). Multiple fonts may be
              listed in case multiple languages must be supported.
            '';
          };

          sansSerif = mkOption {
            type = types.listOf types.str;
            default = ["DejaVu Sans"];
            description = ''
              System-wide default sans serif font(s). Multiple fonts may be
              listed in case multiple languages must be supported.
            '';
          };

          serif = mkOption {
            type = types.listOf types.str;
            default = ["DejaVu Serif"];
            description = ''
              System-wide default serif font(s). Multiple fonts may be listed
              in case multiple languages must be supported.
            '';
          };

          emoji = mkOption {
            type = types.listOf types.str;
            default = ["Noto Color Emoji"];
            description = ''
              System-wide default emoji font(s). Multiple fonts may be listed
              in case a font does not support all emoji.

              Note that fontconfig matches color emoji fonts preferentially,
              so if you want to use a black and white font while having
              a color font installed (eg. Noto Color Emoji installed alongside
              Noto Emoji), fontconfig will still choose the color font even
              when it is later in the list.
            '';
          };
        };

        hinting = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = ''
              Enable font hinting. Hinting aligns glyphs to pixel boundaries to
              improve rendering sharpness at low resolution. At high resolution
              (> 200 dpi) hinting will do nothing (at best); users of such
              displays may want to disable this option.
            '';
          };

          autohint = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Enable the autohinter in place of the default interpreter.
              The results are usually lower quality than correctly-hinted
              fonts, but better than unhinted fonts.
            '';
          };
        };

        includeUserConf = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Include the user configuration from
            <filename>~/.config/fontconfig/fonts.conf</filename> or
            <filename>~/.config/fontconfig/conf.d</filename>.
          '';
        };

        subpixel = {

          rgba = mkOption {
            default = "rgb";
            type = types.enum ["rgb" "bgr" "vrgb" "vbgr" "none"];
            description = ''
              Subpixel order. The overwhelming majority of displays are
              <literal>rgb</literal> in their normal orientation. Select
              <literal>vrgb</literal> for mounting such a display 90 degrees
              clockwise from its normal orientation or <literal>vbgr</literal>
              for mounting 90 degrees counter-clockwise. Select
              <literal>bgr</literal> in the unlikely event of mounting 180
              degrees from the normal orientation. Reverse these directions in
              the improbable event that the display's native subpixel order is
              <literal>bgr</literal>.
            '';
          };

          lcdfilter = mkOption {
            default = "default";
            type = types.enum ["none" "default" "light" "legacy"];
            description = ''
              FreeType LCD filter. At high resolution (> 200 DPI), LCD filtering
              has no visible effect; users of such displays may want to select
              <literal>none</literal>.
            '';
          };

        };

        cache32Bit = mkOption {
          default = false;
          type = types.bool;
          description = ''
            Generate system fonts cache for 32-bit applications.
          '';
        };

        allowBitmaps = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Allow bitmap fonts. Set to <literal>false</literal> to ban all
            bitmap fonts.
          '';
        };

        allowType1 = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Allow Type-1 fonts. Default is <literal>false</literal> because of
            poor rendering.
          '';
        };

        useEmbeddedBitmaps = mkOption {
          type = types.bool;
          default = false;
          description = ''Use embedded bitmaps in fonts like Calibri.'';
        };

      };

    };

  };
  config = mkMerge [
    (mkIf cfg.enable {
      environment.systemPackages    = [ pkgs.fontconfig ];
      environment.etc.fonts.source  = "${fontconfigEtc}/etc/fonts/";
    })
    (mkIf cfg.enable {
      fonts.fontconfig.confPackages = [ confPkg ];
    })
  ];

}

{ self, inputs, ... }:
{
  flake.nixosModules.hyprland =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      inherit (config) modules;
      inherit (modules.programs) default;

      noctaliaExe = lib.getExe config.hm.programs.noctalia.package;
      grimblast = lib.getExe pkgs.grimblast;

      toLua = lib.generators.toLua { };
      lua = lib.generators.mkLuaInline;

      # Home Manager's Lua serializer turns {_args = [...];} into a
      # multi-argument hl.bind(...) call. The dispatcher must be raw Lua,
      # hence mkLuaInline.
      mkBind = keys: dispatcher: {
        _args = [
          keys
          (lua dispatcher)
        ];
      };

      mkBindWith = keys: dispatcher: flags: {
        _args = [
          keys
          (lua dispatcher)
          flags
        ];
      };

      modKey = key: lua "mod .. ${toLua " + ${key}"}";

      modShiftKey = key: lua "mod .. ${toLua " + SHIFT + ${key}"}";

      exec = command: "hl.dsp.exec_cmd(${toLua command})";
      hermesVoiceExe = "${config.hm.home.profileDirectory}/bin/hermes-voice";

      workspaceBinds = builtins.concatLists (
        builtins.genList (
          x:
          let
            workspace = x + 1;
            key = if workspace == 10 then "0" else toString workspace;
          in
          [
            (mkBind (modKey key) "hl.dsp.focus({ workspace = ${toString workspace} })")
            (mkBind "ALT + ${key}" "hl.dsp.focus({ workspace = ${toString workspace} })")
            (mkBind (modShiftKey key) "hl.dsp.window.move({ workspace = ${toString workspace} })")
          ]
        ) 10
      );
    in
    {
      hm.wayland.windowManager.hyprland.settings = {
        # Lua has one bind entry point. Former bindm/bindle behavior is
        # represented by the flags table passed as the third argument.
        bind = [
          # Mouse move / resize.
          (mkBindWith (modKey "mouse:272") "hl.dsp.window.drag()" { mouse = true; })
          (mkBindWith (modKey "mouse:273") "hl.dsp.window.resize()" { mouse = true; })

          # UWSM users should not call Hyprland's exit dispatcher directly.
          (mkBind (modKey "M") (exec "uwsm stop"))

          (mkBind (modKey "Q") "hl.dsp.window.close()")
          (mkBind (modKey "F") ''hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })'')
          (mkBind (modShiftKey "SPACE") ''hl.dsp.window.float({ action = "toggle" })'')

          # The old unnamed special workspace is represented as a named
          # scratchpad because the current Lua dispatcher explicitly takes a
          # special-workspace name.
          (mkBind (modKey "y") ''hl.dsp.window.move({ workspace = "special:scratchpad" })'')
          (mkBind (modKey "t") ''hl.dsp.workspace.toggle_special("scratchpad")'')
          (mkBind (modKey "G") ''hl.dsp.workspace.toggle_special("hermes-browser")'')

          (mkBind (modKey "h") ''hl.dsp.focus({ direction = "l" })'')
          (mkBind (modKey "l") ''hl.dsp.focus({ direction = "r" })'')
          (mkBind (modKey "k") ''hl.dsp.focus({ direction = "u" })'')
          (mkBind (modKey "j") ''hl.dsp.focus({ direction = "d" })'')

          (mkBind (modShiftKey "h") ''hl.dsp.window.move({ direction = "l" })'')
          (mkBind (modShiftKey "l") ''hl.dsp.window.move({ direction = "r" })'')
          (mkBind (modShiftKey "k") ''hl.dsp.window.move({ direction = "u" })'')
          (mkBind (modShiftKey "j") ''hl.dsp.window.move({ direction = "d" })'')

          (mkBind (modKey "B") ''hl.dsp.workspace.move({ monitor = "DP-2" })'')
          (mkBind (modShiftKey "B") ''hl.dsp.workspace.move({ monitor = "DP-1" })'')

          (mkBind (modKey "I") (exec "${noctaliaExe} msg session lock"))
          (mkBind (modShiftKey "I") (exec "${noctaliaExe} msg session lock-and-suspend"))

          (mkBind (modKey "Return") (exec "${default.terminal} start --always-new-process"))
          (mkBind (modShiftKey "Return") (exec "${default.terminal}"))
          (mkBind (modKey "E") (exec "${default.fileManager}"))

          (mkBindWith (modKey "V") (exec hermesVoiceExe) {
            dont_inhibit = true;
          })
          (mkBindWith (modShiftKey "V") ''hl.dsp.workspace.toggle_special("hermes")'' {
            dont_inhibit = true;
          })

          (mkBind (modKey "U") (exec "ags -b hypr -r 'recorder.start()'"))
          (mkBind (modKey "P") (exec "${grimblast} --notify copysave output"))
          (mkBind (modShiftKey "P") (exec "${grimblast} --notify copysave area"))
          (mkBind (modKey "SPACE") (exec "${noctaliaExe} msg panel-toggle launcher"))

          # Former bindle = locked + repeating.
          (mkBindWith "XF86MonBrightnessUp" (exec "${noctaliaExe} msg brightness-up") {
            locked = true;
            repeating = true;
          })
          (mkBindWith "XF86MonBrightnessDown" (exec "${noctaliaExe} msg brightness-down") {
            locked = true;
            repeating = true;
          })
          (mkBindWith "XF86AudioRaiseVolume" (exec "${noctaliaExe} msg volume-up") {
            locked = true;
            repeating = true;
          })
          (mkBindWith "XF86AudioLowerVolume" (exec "${noctaliaExe} msg volume-down") {
            locked = true;
            repeating = true;
          })
          (mkBindWith "XF86AudioMute" (exec "${noctaliaExe} msg volume-mute") {
            locked = true;
            repeating = true;
          })
        ]
        ++ workspaceBinds;
      };
    };
}

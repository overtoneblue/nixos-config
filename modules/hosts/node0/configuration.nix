{ self, inputs, ... }:
{

  flake.nixosModules.node0Configuration =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      imports = [
        self.nixosModules.options
        ./_system.nix
        self.nixosModules.node0Hardware
        self.nixosModules.base
        self.nixosModules.nix-settings
        self.nixosModules.network
        self.nixosModules.sound
        self.nixosModules.niri
        self.nixosModules.gaming
        inputs.home-manager.nixosModules.home-manager
        (lib.mkAliasOptionModule [ "hm" ] [ "home-manager" "users" "cenunix" ])
        self.nixosModules.theme
        self.nixosModules.hyprland
        self.nixosModules.nvf
        self.nixosModules.myNeovim
        self.nixosModules.firefox
      ];

      hm.home.username = "cenunix";
      hm.home.homeDirectory = "/home/cenunix";
      hm.home.stateVersion = "25.11";
      hm.home.packages = with pkgs; [
        wl-clipboard
        gist # manage github gists
        act # local github actions
        zsh-forgit # zsh plugin to load forgit via `git forgit`
        gitflow
        ripgrep # recursively searches directories for a regex pattern
        plexamp
      ];
      hm.programs = {

        wezterm = {
          enable = true;
          enableZshIntegration = true;
          extraConfig = ''
            local wezterm = require 'wezterm'
            local mux = wezterm.mux
            local config = wezterm.config_builder()
            local act = wezterm.action
            config.max_fps = 240
            config.animation_fps = 240
            config.use_fancy_tab_bar = false
            config.front_end = "OpenGL"
            config.enable_wayland = true
            config.keys = {
              {
                key = 'i',
                mods = 'CTRL',
                action = act.EmitEvent 'workflow-startup',
              },
              {
                key = 'i',
                mods = 'CTRL|SHIFT',
                action = act.SwitchToWorkspace {
                  name = 'workflow',
                },
              },
              {
                key = 'u',
                mods = 'CTRL|SHIFT',
                action = act.SwitchToWorkspace {
                  name = 'default',
                },
              },
            }

            wezterm.on('workflow-startup', function(cmd)
              -- allow `wezterm start -- something` to affect what we spawn
              -- in our initial window
              local args = {}
              if cmd then
                args = cmd.args
              end

              local journal_dir = '/home/cenunix/Personal/Janaru'
              local config_dir = '/home/cenunix/NixLand'
              local default_dir = '/home/cenunix'
              local default_tab, default_pane, window = mux.spawn_window {
                workspace = 'workflow',
                cwd = default_dir,
                args = args,
              }
              local config_tab, config_pane, window = window:spawn_tab {
                cwd = config_dir,
              }
              local journal_tab, journal_pane, window = window:spawn_tab {
                cwd = journal_dir,
              }
              local music_tab, music_pane, window = window:spawn_tab {
                cwd = default_dir,
              }

              journal_tab:set_title 'Journal'
              config_tab:set_title 'NixLand'
              music_tab:set_title 'Music'

              config_pane:send_text 'nvim .\n'
              journal_pane:send_text 'nvim .\n'
              music_pane:send_text 'spotify_player \n'
              default_tab:activate()



              -- We want to startup in the workflow workspace
              mux.set_active_workspace 'workflow'
            end)
            return config
          '';
        };
        dircolors = {
          enable = true;
          enableZshIntegration = true;
        };
        bash = {
          enable = true;
          initExtra = "SHELL=${pkgs.bash}";
        };
        starship = {
          enable = true;
          settings = {
            add_newline = false;
            scan_timeout = 5;
            character = {
              error_symbol = "[󰊠](bold red)";
              success_symbol = "[󰊠](bold green)";
              vicmd_symbol = "[󰊠](bold yellow)";
              format = "$symbol [|](bold bright-black) ";
            };
            git_commit = {
              commit_hash_length = 4;
            };
            line_break.disabled = false;
            lua.symbol = "[](blue) ";
            python.symbol = "[](blue) ";
            hostname = {
              ssh_only = true;
              format = "[$hostname](bold blue) ";
              disabled = false;
            };
          };
        };

        zsh = {
          enable = true;
          enableCompletion = true;
          autosuggestion.enable = true;
          syntaxHighlighting.enable = true;
          dotDir = "/home/cenunix/.config/zsh";
          sessionVariables = {
            LC_ALL = "en_US.UTF-8";
            ZSH_AUTOSUGGEST_USE_ASYNC = "true";
            SSH_AUTH_SOCK = "/run/user/1000/keyring/ssh";
            GOPATH = "$HOME/.local/share/go";
          };
          initContent = ''
            path+="$HOME/.local/share/go/bin"
          '';
          history = {
            save = 1000;
            size = 1000;
            expireDuplicatesFirst = true;
            ignoreDups = true;
            ignoreSpace = true;
          };
        };

        # a command-line tool for github
        gh = {
          enable = true;
          gitCredentialHelper.enable = true;
          extensions = with pkgs; [
            gh-dash # dashboard with pull requests and issues
            gh-eco # explore the ecosystem
            gh-cal # contributions calender terminal viewer
          ];
          settings = {
            version = 1;
            git_protocol = "ssh";
            prompt = "enabled";
          };
        };

        git = {
          enable = true;
          # package = pkgs.gitAndTools.gitFull;
          ignores = [
            ".cache/"
            ".idea/"
            "*.swp"
            "*.elc"
            ".~lock*"
            "auto-save-list"
            ".direnv/"
            "node_modules"
            "result"
            "result-*"
          ];

          lfs.enable = true;

          settings = {
            user.name = "cenunix";
            user.email = "user55596@protonmail.com";

            init.defaultBranch = "main";
            credential.helper = "oauth";
            delta = {
              enable = true;
              line-numbers = true;
              options.navigate = true;
            };

            branch.autosetupmerge = "true";
            pull.ff = "only";
            http.postBuffer = "524288000";
            push = {
              default = "current";
              followTags = true;
            };

            merge = {
              stat = "true";
              conflictstyle = "diff3";
            };

            core.whitespace = "fix,-indent-with-non-tab,trailing-space,cr-at-eol";
            color.ui = "auto";

            repack.usedeltabaseoffset = "true";

            rebase = {
              autoSquash = true;
              autoStash = true;
            };

            rerere = {
              autoupdate = true;
              enabled = true;
            };

            url = {
              "https://github.com/".insteadOf = "github:";
              "ssh://git@github.com/".pushInsteadOf = "github:";
              "https://gitlab.com/".insteadOf = "gitlab:";
              "ssh://git@gitlab.com/".pushInsteadOf = "gitlab:";
              "https://aur.archlinux.org/".insteadOf = "aur:";
              "ssh://aur@aur.archlinux.org/".pushInsteadOf = "aur:";
              "https://git.sr.ht/".insteadOf = "srht:";
              "ssh://git@git.sr.ht/".pushInsteadOf = "srht:";
              "https://codeberg.org/".insteadOf = "codeberg:";
              "ssh://git@codeberg.org/".pushInsteadOf = "codeberg:";
            };

            alias = {
              br = "branch";
              c = "commit -m";
              ca = "commit -am";
              co = "checkout";
              d = "diff";
              df = "!git hist | peco | awk '{print $2}' | xargs -I {} git diff {}^ {}";
              edit-unmerged = "!f() { git ls-files --unmerged | cut -f2 | sort -u ; }; vim `f`";
              fuck = "commit --amend -m";
              graph = "log --all --decorate --graph";
              ps = "!git push origin $(git rev-parse --abbrev-ref HEAD)";
              pl = "!git pull origin $(git rev-parse --abbrev-ref HEAD)";
              af = "!git add $(git ls-files -m -o --exclude-standard | fzf -m)";
              st = "status";
              hist = ''
                log --pretty=format:"%Cgreen%h %Creset%cd %Cblue[%cn] %Creset%s%C(yellow)%d%C(reset)" --graph --date=relative --decorate --all
              '';
              llog = ''
                log --graph --name-status --pretty=format:"%C(red)%h %C(reset)(%cd) %C(green)%an %Creset%s %C(yellow)%d%Creset" --date=relative
              '';
            };
          };
        };
      };

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];

      boot = {
        kernelPackages = pkgs.linuxPackages;
        loader = {
          systemd-boot.enable = true;
          efi.canTouchEfiVariables = true;
        };
      };

      networking.hostName = "node0"; # Define your hostname.

      environment.systemPackages = with pkgs; [
        git
        thunar
        firefox
        zed
        helix
        vscode
      ];
    };
}

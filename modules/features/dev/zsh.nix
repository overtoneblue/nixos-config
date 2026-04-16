{
  inputs,
  ...
}:

{
  perSystem =
    {
      pkgs,
      self',
      ...
    }:

    {
      packages.myZsh = inputs.wrapper-modules.wrappers.zsh.wrap {
        inherit pkgs;

        # Optional: if global zsh rc files on the host cause trouble
        # skipGlobalRC = true;

        # Safe to null if not using standalone Home Manager on the target machine
        hmSessionVariables = null;

        zshenv.content = ''
          export LC_ALL="en_US.UTF-8"
          export ZSH_AUTOSUGGEST_USE_ASYNC="true"
          export EDITOR="nvim"
          export VISUAL="nvim"
        '';

        zshAliases = {
          ll = "eza -lah";
          ls = "eza";
          v = "nvim";
        };

        zshrc.content = ''
          # history
          HISTSIZE=1000
          SAVEHIST=1000
          setopt HIST_IGNORE_DUPS
          setopt HIST_IGNORE_SPACE
          setopt HIST_EXPIRE_DUPS_FIRST
          setopt AUTO_CD
          setopt EXTENDED_GLOB

          # completion
          autoload -Uz compinit
          compinit

          # prompt / tools
          eval "$(${self'.packages.myStarship}/bin/starship init zsh)"
          eval "$(${pkgs.direnv}/bin/direnv hook zsh)"


          # optional niceties if installed
          if command -v zoxide >/dev/null 2>&1; then
            eval "$(zoxide init zsh)"
          fi

          if command -v fzf >/dev/null 2>&1; then
            source ${pkgs.fzf}/share/fzf/key-bindings.zsh
            source ${pkgs.fzf}/share/fzf/completion.zsh
          fi

          if command -v dircolors >/dev/null 2>&1; then
            eval "$(dircolors -b)"
          fi

          # autosuggestions / syntax highlighting from nixpkgs packages
          source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
          source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
        '';
      };
    };
}

{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  osConfig,
  ...
}:
{
  config.vim = {
    formatter = {
      conform-nvim = {
        enable = true;

        setupOpts.format_on_save = {
          lsp_format = "fallback";
          timeout_ms = 500;
          enabled = true;
          callbacks = {
            # wrap your Lua function in a Nix multi-line string:
            start = ''
              function(bufnr)
                vim.notify("Conform formatting: " .. vim.api.nvim_buf_get_name(bufnr))
                print("Conform formatting:", vim.api.nvim_buf_get_name(bufnr))
              end
            '';
            done = ''
              function(bufnr, paths)
                print("Conform finished:", vim.api.nvim_buf_get_name(bufnr))
              end
            '';
          };
        };
      };
    };
    diagnostics = {
      enable = true;
      config = {
        underline = {
          severity = {
            min = lib.generators.mkLuaInline "vim.diagnostic.severity.ERROR";
          };
        };
        virtual_text = false;
        signs = true;
        float = true;
      };
    };
    lsp = {
      enable = true;
      formatOnSave = true;
      lspkind.enable = true;
    };
    languages = {
      enableDAP = true;
      enableFormat = true;
      enableTreesitter = true;
      enableExtraDiagnostics = true;
      nix = {
        enable = true;
        # format.package = pkgs.nixfmt-rfc-style;
        format.type = [ "nixfmt" ];
      };
      python = {
        enable = true;
        format.enable = true;
        lsp.enable = true;
        extraDiagnostics = {
          enable = true;
        };
      };
      lua = {
        enable = true;
      };

    };
  };
}

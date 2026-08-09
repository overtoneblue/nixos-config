{
  self,
  inputs,
  ...
}:
{
  config.vim.luaConfigPost = ''
    -- Java/JDTLS: disable semantic tokens because they were causing broken-looking highlighting.
    vim.api.nvim_create_autocmd("LspAttach", {
      group = vim.api.nvim_create_augroup("JavaDisableSemanticTokens", { clear = true }),
      callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if not client then
          return
        end

        if client.name == "jdt-language-server" or client.name == "jdtls" then
          -- Newer Neovim API. This is the command that fixed it manually:
          -- :lua vim.lsp.semantic_tokens.enable(false)
          pcall(vim.lsp.semantic_tokens.enable, false, { bufnr = args.buf })

          -- Extra safety: prevent this client from advertising semantic tokens further.
          if client.server_capabilities then
            client.server_capabilities.semanticTokensProvider = nil
          end

          -- Optional: disable Java inlay hints too, since they can make beginner Java files noisy.
          if vim.lsp.inlay_hint then
            pcall(vim.lsp.inlay_hint.enable, false, { bufnr = args.buf })
          end
        end
      end,
    })

    -- Java display sanity settings.
    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("JavaDisplaySanity", { clear = true }),
      pattern = "java",
      callback = function()
        vim.opt_local.conceallevel = 0

        vim.diagnostic.config({
          virtual_text = false,
          virtual_lines = false,
          signs = true,
          underline = true,
          update_in_insert = false,
        })
      end,
    })
  '';
  config.vim = {
    viAlias = false;
    vimAlias = true;
    preventJunkFiles = true;
    enableLuaLoader = true;

    options = {
      shell = "zsh";
      guifont = "Inter Nerd Font:h14";
      termguicolors = true;
      undofile = true;
      smartindent = true;
      tabstop = 2;
      shiftwidth = 2;
      shiftround = true;
      expandtab = true;
      cursorline = true;
      # textwidth = 80;
      wrap = true;
      linebreak = true;
      relativenumber = true;
      number = true;
      viminfo = "";
      viminfofile = "NONE";
      clipboard = "unnamedplus";
      splitright = true;
      splitbelow = true;
      laststatus = 0;
      cmdheight = 1;
      winborder = "rounded";
    };
  };
}

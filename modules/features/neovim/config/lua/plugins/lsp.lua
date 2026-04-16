vim.diagnostic.config({
	underline = {
		severity = { min = vim.diagnostic.severity.ERROR },
	},
	virtual_text = false,
	signs = true,
	float = true,
})

-- Lua
vim.lsp.config("lua_ls", {
	settings = {
		Lua = {
			diagnostics = {
				globals = { "vim" },
			},
			workspace = {
				checkThirdParty = false,
			},
			telemetry = {
				enable = false,
			},
		},
	},
})

-- Nix
vim.lsp.config("nil_ls", {})

-- Python
vim.lsp.config("pyright", {})

vim.lsp.enable("lua_ls")
vim.lsp.enable("nil_ls")
vim.lsp.enable("pyright")

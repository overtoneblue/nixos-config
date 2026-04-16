local ok, conform = pcall(require, "conform")
if not ok then
	return
end

conform.setup({
	formatters_by_ft = {
		lua = { "stylua" },
		nix = { "nixfmt" },
		python = { "isort", "black" },
	},

	format_on_save = {
		lsp_format = "fallback",
		timeout_ms = 500,
	},
})

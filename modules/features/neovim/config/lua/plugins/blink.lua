local ok, blink = pcall(require, "blink.cmp")
if not ok then
	return
end

blink.setup({
	snippets = {
		preset = "luasnip",
	},
	completion = {
		ghost_text = {
			enabled = true,
		},
		trigger = {
			prefetch_on_insert = false,
		},
	},
	keymap = {
		["<C-e>"] = { "hide" },
		["<C-y>"] = { "accept" },
	},
	sources = {
		default = { "lsp", "path", "snippets", "buffer" },
	},
	appearance = {
		kind_icons = {
			Ollama = "󰳆",
		},
	},
})

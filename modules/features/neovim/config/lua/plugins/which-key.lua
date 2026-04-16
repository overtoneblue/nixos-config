local ok, wk = pcall(require, "which-key")
if not ok then
	return
end

wk.setup({
	preset = "classic",
	delay = 0,
	icons = {
		mappings = false,
		separator = "➜",
		group = "",
	},
	triggers = {
		{ "<leader>", mode = "n" },
	},
})

wk.add({
	{ "<leader>f", group = " Picker" },
	{ "<leader>g", group = " Git" },
	{ "<leader>t", group = " Terminal" },
	{ "<leader>l", group = " LSP" },
	{ "<leader>c", group = " Spellcheck" },
	{ "<leader>cl", group = "󰗊 Language" },
	{ "<leader>o", group = " Obsidian" },
	{ "<leader>d", group = "Debug" },
	{ "<leader>h", group = "" },
})

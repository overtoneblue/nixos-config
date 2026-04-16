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
			show_in_snippet = false,
		},
	},

	keymap = {
		preset = "none",

		["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
		["<C-e>"] = { "hide", "fallback" },
		["<C-y>"] = { "select_and_accept", "fallback" },

		["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
		["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },

		["<Up>"] = { "select_prev", "fallback" },
		["<Down>"] = { "select_next", "fallback" },
		["<C-p>"] = { "select_prev", "fallback_to_mappings" },
		["<C-n>"] = { "select_next", "fallback_to_mappings" },

		["<C-b>"] = { "scroll_documentation_up", "fallback" },
		["<C-f>"] = { "scroll_documentation_down", "fallback" },

		["<C-k>"] = { "show_signature", "hide_signature", "fallback" },
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

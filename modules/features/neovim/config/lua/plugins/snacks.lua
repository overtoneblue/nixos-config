local ok, snacks = pcall(require, "snacks")
if not ok then
	return
end

snacks.setup({
	explorer = {
		replace_netrw = true,
	},
	picker = {
		layout = {
			preset = "telescope",
		},
		sources = {
			explorer = {
				jump = {
					close = true,
				},
				layout = {
					preset = "telescope",
					preview = true,
				},
			},
		},
	},
	input = {
		enabled = true,
	},
	notifier = {
		enabled = true,
	},
	statuscolumn = {
		enabled = true,
	},
	scroll = {
		enabled = true,
	},
	image = {
		enabled = true,
		doc = {
			float = true,
			max_width = 20,
			max_height = 10,
		},
	},
})

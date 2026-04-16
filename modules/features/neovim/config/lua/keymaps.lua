local map = vim.keymap.set
local opts = { noremap = true, silent = true }

-- Basic
map("n", "<leader>w", "<cmd>w<cr>", vim.tbl_extend("force", opts, { desc = "Save Buffer" }))
map("n", "<leader>q", "<cmd>q<cr>", vim.tbl_extend("force", opts, { desc = "Quit" }))
map("n", "<leader>e", function()
	require("snacks").explorer()
end, vim.tbl_extend("force", opts, { desc = "Explorer" }))
map("n", "<leader>c", ":bdelete!<CR>", vim.tbl_extend("force", opts, { desc = "Close Buffer" }))
map("n", "gb", function()
	require("snipe").open_buffer_menu()
end, vim.tbl_extend("force", opts, { desc = "Snipe Buffers" }))

-- Picker
map("n", "<leader>ff", function()
	require("snacks").picker.files()
end, vim.tbl_extend("force", opts, { desc = "Find File" }))
map("n", "<leader>fr", function()
	require("snacks").picker.recent()
end, vim.tbl_extend("force", opts, { desc = "Open Recent File" }))
map("n", "<leader>fn", "<cmd>enew<cr>", vim.tbl_extend("force", opts, { desc = "New File" }))
map("n", "<leader>fw", function()
	require("snacks").picker.grep()
end, vim.tbl_extend("force", opts, { desc = "Grep Files" }))
map("n", "<leader>fb", function()
	require("snacks").picker.buffers()
end, vim.tbl_extend("force", opts, { desc = "Grep Buffers" }))
map("n", "<leader>fh", function()
	require("snacks").picker.help()
end, vim.tbl_extend("force", opts, { desc = "Grep Help Tags" }))
map("n", "<leader>fg", function()
	require("snacks").picker.git_files()
end, vim.tbl_extend("force", opts, { desc = "Grep Git Files" }))
map("n", "<leader>fd", function()
	require("snacks").picker.diagnostics()
end, vim.tbl_extend("force", opts, { desc = "Grep Diagnostics" }))
map("n", "<leader>fc", function()
	require("aerial").snacks_picker()
end, vim.tbl_extend("force", opts, { desc = "Code Outline" }))

-- Terminal
map("n", "<leader>tt", "<cmd>ToggleTerm<cr>", vim.tbl_extend("force", opts, { desc = "Toggle Terminal" }))
map(
	"n",
	"<leader>tf",
	"<cmd>ToggleTerm direction=float<cr>",
	vim.tbl_extend("force", opts, { desc = "Toggle Float Terminal" })
)
map("t", "<Esc>", [[<C-\><C-n>]], vim.tbl_extend("force", opts, { desc = "Exit Insert Mode" }))

-- Git
map("n", "<leader>gl", "<cmd>Gitsigns blame_line<cr>", vim.tbl_extend("force", opts, { desc = "View Git Blame" }))
map(
	"n",
	"<leader>gL",
	"<cmd>Gitsigns blame_line {full = true}<cr>",
	vim.tbl_extend("force", opts, { desc = "View full Git Blame" })
)
map("n", "<leader>gp", "<cmd>Gitsigns preview_hunk<cr>", vim.tbl_extend("force", opts, { desc = "Preview Git Hunk" }))
map("n", "<leader>gh", "<cmd>Gitsigns reset_hunk<cr>", vim.tbl_extend("force", opts, { desc = "Reset Git Hunk" }))
map("n", "<leader>gr", "<cmd>Gitsigns reset_buffer<cr>", vim.tbl_extend("force", opts, { desc = "Reset Git Buffer" }))
map("n", "<leader>gs", "<cmd>Gitsigns stage_hunk<cr>", vim.tbl_extend("force", opts, { desc = "Stage Git Hunk" }))
map("n", "<leader>gS", "<cmd>Gitsigns stage_buffer<cr>", vim.tbl_extend("force", opts, { desc = "Stage Git Buffer" }))
map(
	"n",
	"<leader>gu",
	"<cmd>Gitsigns undo_stage_hunk<cr>",
	vim.tbl_extend("force", opts, { desc = "Unstage Git Hunk" })
)
map("n", "<leader>gd", "<cmd>Gitsigns diffthis<cr>", vim.tbl_extend("force", opts, { desc = "View Git Diff" }))

-- LSP
map("n", "<leader>li", "<cmd>LspInfo<cr>", vim.tbl_extend("force", opts, { desc = "LSP Information" }))
map("n", "<leader>lI", "<cmd>NullLsInfo<cr>", vim.tbl_extend("force", opts, { desc = "Null-ls Information" }))
map("n", "<leader>la", vim.lsp.buf.code_action, vim.tbl_extend("force", opts, { desc = "LSP Code Action" }))
map("n", "<leader>lh", vim.lsp.buf.signature_help, vim.tbl_extend("force", opts, { desc = "Signature Help" }))
map("n", "<leader>lr", vim.lsp.buf.rename, vim.tbl_extend("force", opts, { desc = "Rename Current Symbol" }))
map("n", "<leader>ll", vim.lsp.codelens.refresh, vim.tbl_extend("force", opts, { desc = "LSP CodeLens Refresh" }))
map("n", "<leader>lL", vim.lsp.codelens.run, vim.tbl_extend("force", opts, { desc = "LSP CodeLens Run" }))
map(
	"n",
	"<leader>lR",
	"<cmd>Telescope lsp_references<cr>",
	vim.tbl_extend("force", opts, { desc = "Search References" })
)

-- Goto
map("n", "gd", "<cmd>Telescope lsp_definitions<cr>", vim.tbl_extend("force", opts, { desc = "Goto Definition" }))
map(
	"n",
	"gI",
	"<cmd>Telescope lsp_implementations<cr>",
	vim.tbl_extend("force", opts, { desc = "Goto Implementation" })
)
map("n", "gr", "<cmd>Telescope lsp_references<cr>", vim.tbl_extend("force", opts, { desc = "Search References" }))
map("n", "gl", vim.diagnostic.open_float, vim.tbl_extend("force", opts, { desc = "Hover Diagnostics" }))
map(
	"n",
	"gy",
	"<cmd>Telescope lsp_type_definitions<cr>",
	vim.tbl_extend("force", opts, { desc = "Definition of Current Type" })
)

-- Buffer nav
map("n", "<S-h>", "<cmd>BufferLineCyclePrev<cr>", vim.tbl_extend("force", opts, { desc = "Left Buffer" }))
map("n", "<S-l>", "<cmd>BufferLineCycleNext<cr>", vim.tbl_extend("force", opts, { desc = "Right Buffer" }))
map("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "Hover Symbol Details" }))

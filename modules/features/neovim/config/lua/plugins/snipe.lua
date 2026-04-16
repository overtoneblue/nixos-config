local ok, snipe = pcall(require, "snipe")
if not ok then
	return
end

snipe.setup({})

local C = {}

C.defaults = {
	env_file = ".env",
	window_width = 150,
	window_height = 100,
	dir = ".",
}

C.options = vim.deepcopy(C.opts)

return C

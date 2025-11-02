local C = {}

C.defaults = {
	env_file = ".env",
	window_width = 40,
	window_height = 20,
	dir = ".",
}

C.options = vim.deepcopy(C.opts)

return C

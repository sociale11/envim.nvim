local M = {}

local config = require("envim.config")
local ui = require("envim.ui")

function M.setup()
	config.options = vim.tbl_extend("force", config.defaults, config.options or {})
	print("Envim loaded")
end

return M

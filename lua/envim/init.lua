local M = {}

--- Initializes the plugin with default configuration
function M.setup()
	local config = require("envim.config")
	config.options = vim.tbl_extend("force", config.defaults, config.options or {})
	print("Envim loaded")
end

--- Opens the environment variable manager UI
function M.open()
	local config = require("envim.config")
	local parser = require("envim.parser")
	local ui = require("envim.ui")

	local cwd = vim.fn.getcwd()
	local env_file_path = cwd .. "/" .. config.options.env_file

	local env_vars, err = parser.parse_env_file(env_file_path)

	if not env_vars then
		vim.notify("Error: " .. (err or "Unknown error"), vim.log.levels.ERROR)
		return
	end

	if #env_vars == 0 then
		vim.notify("No environment variables found", vim.log.levels.WARN)
		return
	end

	ui.show_popup(env_vars, config.options, env_file_path)
end

return M

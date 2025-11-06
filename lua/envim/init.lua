local M = {}

--- Initializes the plugin with default configuration
function M.setup()
	print("Envim loaded")
end

--- Finds the first available .env file in the current directory
--- @return string|nil filepath Path to the .env file or nil if not found
local function find_env_file()
	local cwd = vim.fn.getcwd()
	local candidates = { ".env", ".env.local", ".env.development", ".env.production", ".env.test" }

	for _, filename in ipairs(candidates) do
		local filepath = cwd .. "/" .. filename
		local file = io.open(filepath, "r")
		if file then
			file:close()
			return filepath
		end
	end

	return nil
end

--- Opens the environment variable manager UI
function M.open()
	local parser = require("envim.parser")
	local ui = require("envim.ui")

	local env_file_path = find_env_file()

	if not env_file_path then
		vim.notify("No .env file found in current directory", vim.log.levels.ERROR)
		return
	end

	local env_vars, err = parser.parse_env_file(env_file_path)

	if not env_vars then
		vim.notify("Error: " .. (err or "Unknown error"), vim.log.levels.ERROR)
		return
	end

	if #env_vars == 0 then
		vim.notify("No environment variables found", vim.log.levels.WARN)
		return
	end

	ui.show_popup(env_vars, env_file_path)
end

return M

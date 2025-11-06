local M = {}

M.selected_env_file = nil

--- Initializes the plugin with default configuration
function M.setup()
	print("Envim loaded")
end

--- Finds all available .env files in the current directory
--- @return table filepaths Array of found .env file paths
local function find_env_files()
	local cwd = vim.fn.getcwd()
	local candidates = { ".env", ".env.local", ".env.development", ".env.production", ".env.test" }
	local found = {}

	for _, filename in ipairs(candidates) do
		local filepath = cwd .. "/" .. filename
		local file = io.open(filepath, "r")
		if file then
			file:close()
			table.insert(found, { path = filepath, name = filename })
		end
	end

	return found
end

--- Opens the environment variable manager UI with file selection
--- @param force_select boolean Force file selection even if one is already remembered
function M.open(force_select)
	local parser = require("envim.parser")
	local ui = require("envim.ui")

	local env_files = find_env_files()

	if #env_files == 0 then
		vim.notify("No .env file found in current directory", vim.log.levels.ERROR)
		return
	end

	local function open_env_file(filepath)
		local env_vars, err = parser.parse_env_file(filepath)

		if not env_vars then
			vim.notify("Error: " .. (err or "Unknown error"), vim.log.levels.ERROR)
			return
		end

		if #env_vars == 0 then
			vim.notify("No environment variables found", vim.log.levels.WARN)
			return
		end

		M.selected_env_file = filepath
		ui.show_popup(env_vars, filepath, env_files)
	end

	if M.selected_env_file and not force_select then
		local file_exists = false
		for _, file in ipairs(env_files) do
			if file.path == M.selected_env_file then
				file_exists = true
				break
			end
		end

		if file_exists then
			open_env_file(M.selected_env_file)
			return
		else
			M.selected_env_file = nil
		end
	end

	if #env_files == 1 then
		open_env_file(env_files[1].path)
	else
		local choices = {}
		for _, file in ipairs(env_files) do
			table.insert(choices, file.name)
		end

		vim.ui.select(choices, {
			prompt = "Select .env file:",
		}, function(choice, idx)
			if choice and idx then
				open_env_file(env_files[idx].path)
			end
		end)
	end
end

return M

local M = {}

--- Parses an environment file and extracts variables with their metadata
--- @param filepath string The path to the .env file
--- @return table|nil env_vars Array of parsed environment variables
--- @return string|nil error Error message if parsing failed
function M.parse_env_file(filepath)
	local file = io.open(filepath, "r")
	if not file then
		return nil, "File not found: " .. filepath
	end

	local env_vars = {}
	local last_comment_label = nil

	for line in file:lines() do
		if line:match("^%s*$") then
			last_comment_label = nil
			goto continue
		end

		local is_commented = line:match("^%s*#") ~= nil

		local parse_line = line
		if is_commented then
			parse_line = line:gsub("^%s*#%s*", "")
		end

		local key, value = parse_line:match("^([^=]+)=(.*)$")

		if key and value then
			key = key:match("^%s*(.-)%s*$")
			value = value:match("^%s*(.-)%s*$")
			value = value:gsub('^"(.-)"$', "%1")
			value = value:gsub("^'(.-)'$", "%1")

			table.insert(env_vars, {
				key = key,
				value = value,
				commented = is_commented,
				label = last_comment_label,
			})
			last_comment_label = nil
		elseif is_commented then
			last_comment_label = parse_line:match("^%s*(.-)%s*$")
		end

		::continue::
	end

	file:close()
	return env_vars
end

--- Saves environment variables to a file
--- @param filepath string The path to the .env file
--- @param env_vars table Array of environment variables to save
--- @return boolean success True if save succeeded
--- @return string|nil error Error message if save failed
function M.save_env_file(filepath, env_vars)
	local file = io.open(filepath, "w")
	if not file then
		return false, "Cannot write to file: " .. filepath
	end

	for _, env in ipairs(env_vars) do
		if env.label then
			local label_text = "# " .. env.label
			file:write(label_text .. "\n")
		end

		local line
		if env.commented then
			line = string.format("# %s=%s", env.key, env.value)
		else
			line = string.format("%s=%s", env.key, env.value)
		end
		file:write(line .. "\n")
	end

	file:close()
	return true
end

return M

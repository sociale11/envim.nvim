local M = {}

function M.parse_env_file(filepath)
	local file = io.open(filepath, "r")
	if not file then
		return nil, "File not found: " .. filepath
	end

	local env_vars = {}
	local last_comment_label = nil

	for line in file:lines() do
		-- Skip empty lines
		if line:match("^%s*$") then
			last_comment_label = nil -- Clear label on empty line
			goto continue
		end

		-- Check if line is commented
		local is_commented = line:match("^%s*#") ~= nil

		-- For commented lines, try to parse after removing #
		local parse_line = line
		if is_commented then
			parse_line = line:gsub("^%s*#%s*", "")
		end

		-- Parse KEY=VALUE
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
				label = last_comment_label, -- Add label from previous comment
			})
			last_comment_label = nil -- Clear after using
		elseif is_commented then
			-- This is a standalone comment line, store as potential label
			last_comment_label = parse_line:match("^%s*(.-)%s*$")
		end

		::continue::
	end

	file:close()
	return env_vars
end

function M.save_env_file(filepath, env_vars)
	local file = io.open(filepath, "w")
	if not file then
		return false, "Cannot write to file: " .. filepath
	end

	for _, env in ipairs(env_vars) do
		-- Write label comment if present
		if env.label then
			local label_text = "# " .. env.label
			local padding = string.rep("#", 100 - #label_text)
			file:write(label_text .. padding .. "\n")
		end

		-- Write the env var line
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

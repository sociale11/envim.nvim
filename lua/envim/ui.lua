local M = {}

--- Displays the environment variable manager popup UI
--- @param env_vars table Array of environment variables
--- @param filepath string Path to the .env file
function M.show_popup(env_vars, filepath)
	local state = {
		all_env_vars = env_vars,
		filtered_vars = env_vars,
		search_query = "",
		filepath = filepath,
		line_to_env_map = {},
		env_to_lines_map = {},
		main_win = nil,
		input_win = nil,
	}

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_option_value("filetype", "sh", { buf = buf })

	local input_buf = vim.api.nvim_create_buf(false, true)

	--- Renders the environment variable list to the buffer
	local function render_list()
		vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

		local lines = {}
		state.line_to_env_map = {}
		state.env_to_lines_map = {}

		for env_idx, env in ipairs(state.filtered_vars) do
			local env_lines = {}

			if env.label then
				table.insert(lines, "# " .. env.label)
				state.line_to_env_map[#lines] = env_idx
				table.insert(env_lines, #lines)
			end

			local line
			if env.commented then
				line = string.format("# %s=%s", env.key, env.value)
			else
				line = string.format("%s=%s", env.key, env.value)
			end
			table.insert(lines, line)
			state.line_to_env_map[#lines] = env_idx
			table.insert(env_lines, #lines)

			state.env_to_lines_map[env_idx] = env_lines
		end

		if #lines == 0 then
			lines = { "No matches found..." }
		end

		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

		local ns_id = vim.api.nvim_create_namespace("envim_indicators")
		vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

		local line_idx = 0
		for env_idx, env in ipairs(state.filtered_vars) do
			if env.label then
				line_idx = line_idx + 1
			end

			if not env.commented then
				vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, 0, {
					virt_text = { { "● ", "Function" } },
					virt_text_pos = "inline",
				})
			end
			line_idx = line_idx + 1
		end

		vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	end

	--- Filters environment variables based on search query
	--- @param query string Search query
	local function update_search(query)
		state.search_query = query
		if query == "" then
			state.filtered_vars = state.all_env_vars
		else
			state.filtered_vars = {}
			for _, env in ipairs(state.all_env_vars) do
				if env.key:lower():find(query:lower(), 1, true) then
					table.insert(state.filtered_vars, env)
				end
			end
		end
		render_list()
	end

	--- Highlights all lines belonging to the current environment variable group
	local function highlight_current_group()
		local ns_id = vim.api.nvim_create_namespace("envim_group_highlight")
		vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

		local win = vim.api.nvim_get_current_win()
		if not vim.api.nvim_win_is_valid(win) then
			return
		end

		local cursor = vim.api.nvim_win_get_cursor(win)
		local current_env_idx = state.line_to_env_map[cursor[1]]

		if current_env_idx then
			local group_lines = state.env_to_lines_map[current_env_idx]
			if group_lines then
				for _, line_num in ipairs(group_lines) do
					vim.api.nvim_buf_add_highlight(buf, ns_id, "CursorLine", line_num - 1, 0, -1)
				end
			end
		end
	end

	--- Toggles the comment status of the current environment variable
	local function toggle_comment()
		local win = vim.api.nvim_get_current_win()
		local cursor = vim.api.nvim_win_get_cursor(win)
		local line_num = cursor[1]

		local env_idx = state.line_to_env_map[line_num]

		if env_idx then
			local env = state.filtered_vars[env_idx]
			env.commented = not env.commented
			render_list()

			local group_lines = state.env_to_lines_map[env_idx]
			if group_lines and #group_lines > 0 then
				vim.api.nvim_win_set_cursor(win, { group_lines[1], 0 })
			end
			highlight_current_group()
		end
	end

	--- Moves cursor to next or previous environment variable group
	--- @param direction number 1 for next, -1 for previous
	local function smart_move(direction)
		local win = vim.api.nvim_get_current_win()
		local cursor = vim.api.nvim_win_get_cursor(win)

		local current_env_idx = state.line_to_env_map[cursor[1]]
		if not current_env_idx then
			return
		end

		local next_env_idx = current_env_idx + direction

		if next_env_idx >= 1 and next_env_idx <= #state.filtered_vars then
			local next_lines = state.env_to_lines_map[next_env_idx]
			if next_lines and #next_lines > 0 then
				vim.api.nvim_win_set_cursor(win, { next_lines[1], 0 })
			end
		end
	end

	--- Saves all environment variables to file
	local function save_changes()
		local parser = require("envim.parser")
		local success, err = parser.save_env_file(filepath, state.all_env_vars)

		if success then
			vim.notify("Saved changes to " .. filepath, vim.log.levels.INFO)
		else
			vim.notify("Error saving: " .. (err or "Unknown error"), vim.log.levels.ERROR)
		end
	end

	--- Prompts user to add a new environment variable
	local function add_variable()
		--- Custom input handler that capitalizes text in real-time
		--- @param prompt string Input prompt text
		--- @param callback function Callback to receive capitalized input
		local function capitalized_input(prompt, callback)
			local autocmd_id = vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
				pattern = "*",
				callback = function(args)
					local buf = args.buf
					local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })

					if buftype == "prompt" or vim.bo[buf].filetype == "snacks_input" then
						local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
						local capitalized = line:upper()

						if line ~= capitalized and line ~= "" then
							local ok, cursor_pos = pcall(vim.api.nvim_win_get_cursor, 0)
							if ok then
								vim.api.nvim_buf_set_lines(buf, 0, 1, false, { capitalized })
								pcall(vim.api.nvim_win_set_cursor, 0, cursor_pos)
							end
						end
					end
				end,
			})

			vim.ui.input({ prompt = prompt }, function(input)
				vim.api.nvim_del_autocmd(autocmd_id)

				if input then
					callback(input:upper())
				else
					callback(input)
				end
			end)
		end

		capitalized_input("Variable name: ", function(key)
			if not key or key == "" then
				return
			end

			vim.ui.input({ prompt = "Variable value: " }, function(value)
				if not value then
					return
				end

				vim.ui.input({ prompt = "Label (optional): " }, function(label)
					local key_exists = false
					for _, env in ipairs(state.all_env_vars) do
						if env.key == key then
							key_exists = true
							break
						end
					end

					local new_var = {
						key = key,
						value = value,
						commented = key_exists,
						label = (label and label ~= "") and label or nil,
					}

					table.insert(state.all_env_vars, new_var)

					update_search(state.search_query)

					vim.notify(string.format("Added variable: %s", key), vim.log.levels.INFO)

					local new_idx = nil
					for i, env in ipairs(state.filtered_vars) do
						if env == new_var then
							new_idx = i
							break
						end
					end
					if new_idx and new_idx > 0 then
						local new_lines = state.env_to_lines_map[new_idx]
						if new_lines and #new_lines > 0 and state.main_win then
							vim.api.nvim_set_current_win(state.main_win)
							vim.api.nvim_win_set_cursor(state.main_win, { new_lines[1], 0 })
							highlight_current_group()
						end
					end
				end)
			end)
		end)
	end

	--- Deletes the current environment variable after confirmation
	local function delete_variable()
		local win = vim.api.nvim_get_current_win()
		local cursor = vim.api.nvim_win_get_cursor(win)
		local env_idx = state.line_to_env_map[cursor[1]]

		if not env_idx then
			return
		end

		local env = state.filtered_vars[env_idx]

		vim.ui.select({ "Yes", "No" }, {
			prompt = string.format("Delete variable '%s'?", env.key),
		}, function(choice)
			if choice ~= "Yes" then
				return
			end

			for i, e in ipairs(state.all_env_vars) do
				if e.key == env.key and e.value == env.value then
					table.remove(state.all_env_vars, i)
					break
				end
			end

			table.remove(state.filtered_vars, env_idx)

			render_list()
			vim.notify(string.format("Deleted variable: %s", env.key), vim.log.levels.INFO)

			if #state.filtered_vars > 0 then
				local new_idx = math.min(env_idx, #state.filtered_vars)
				local new_lines = state.env_to_lines_map[new_idx]
				if new_lines and #new_lines > 0 then
					vim.api.nvim_win_set_cursor(win, { new_lines[1], 0 })
					highlight_current_group()
				end
			end
		end)
	end

	local width = 150
	local max_height = 100
	local total_height = math.min(#env_vars + 10, max_height)
	local row = math.floor((vim.o.lines - total_height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local input_opts = {
		relative = "editor",
		width = width,
		height = 1,
		row = row,
		col = col,
		style = "minimal",
		border = "single",
	}

	local main_height = math.max(10, total_height - 8)
	local main_opts = {
		relative = "editor",
		width = width,
		height = main_height,
		row = row + 3,
		col = col,
		style = "minimal",
		border = "single",
	}

	local input_win = vim.api.nvim_open_win(input_buf, true, input_opts)
	local main_win = vim.api.nvim_open_win(buf, false, main_opts)

	state.input_win = input_win
	state.main_win = main_win

	vim.api.nvim_set_option_value("winhl", "FloatBorder:WinSeparator", { win = input_win })
	vim.api.nvim_set_option_value("winhl", "FloatBorder:WinSeparator", { win = main_win })

	vim.api.nvim_set_option_value("complete", "", { buf = input_buf })
	vim.api.nvim_set_option_value("completeopt", "", { buf = input_buf })
	vim.api.nvim_set_option_value("completefunc", "", { buf = input_buf })
	vim.api.nvim_set_option_value("omnifunc", "", { buf = input_buf })
	vim.api.nvim_buf_set_var(input_buf, "cmp_enabled", false)

	local ok, cmp = pcall(require, "cmp")
	if ok then
		cmp.setup.buffer({
			enabled = false,
		})
	end

	vim.keymap.set("i", "<C-n>", "<Nop>", { buffer = input_buf, nowait = true })
	vim.keymap.set("i", "<C-p>", "<Nop>", { buffer = input_buf, nowait = true })
	vim.keymap.set("i", "<C-x><C-o>", "<Nop>", { buffer = input_buf, nowait = true })
	vim.keymap.set("i", "<C-x><C-n>", "<Nop>", { buffer = input_buf, nowait = true })
	vim.keymap.set("i", "<C-x><C-p>", "<Nop>", { buffer = input_buf, nowait = true })
	vim.keymap.set("i", "<C-x><C-l>", "<Nop>", { buffer = input_buf, nowait = true })
	vim.keymap.set("i", "<C-x><C-f>", "<Nop>", { buffer = input_buf, nowait = true })

	local placeholder_text = "Search environment variables..."
	local placeholder_ns = vim.api.nvim_create_namespace("envim_placeholder")

	--- Shows placeholder text in the search input
	local function show_placeholder()
		vim.api.nvim_buf_clear_namespace(input_buf, placeholder_ns, 0, -1)
		local line = vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1] or ""
		if line == "" then
			vim.api.nvim_buf_set_extmark(input_buf, placeholder_ns, 0, 0, {
				virt_text = { { placeholder_text, "Comment" } },
				virt_text_pos = "overlay",
			})
		end
	end

	--- Clears placeholder text from the search input
	local function clear_placeholder()
		vim.api.nvim_buf_clear_namespace(input_buf, placeholder_ns, 0, -1)
	end

	vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { "" })

	vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged", "InsertCharPre" }, {
		buffer = input_buf,
		callback = function()
			if vim.fn.pumvisible() == 1 then
				vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<C-e>", true, false, true), "n")
			end
		end,
	})

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = input_buf,
		callback = function()
			local line = vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1] or ""

			local capitalized = line:upper()
			if line ~= capitalized and line ~= "" then
				local cursor_pos = vim.api.nvim_win_get_cursor(vim.api.nvim_get_current_win())
				vim.api.nvim_buf_set_lines(input_buf, 0, 1, false, { capitalized })
				vim.api.nvim_win_set_cursor(vim.api.nvim_get_current_win(), cursor_pos)
				line = capitalized
			end

			if line == "" then
				show_placeholder()
			else
				clear_placeholder()
			end
			update_search(line)
		end,
	})

	vim.api.nvim_create_autocmd({ "BufEnter", "InsertLeave" }, {
		buffer = input_buf,
		callback = function()
			show_placeholder()
		end,
	})

	vim.schedule(function()
		show_placeholder()
		vim.cmd("startinsert")
	end)

	render_list()

	vim.keymap.set("i", "<Tab>", function()
		vim.api.nvim_set_current_win(main_win)
		vim.cmd("stopinsert")
		highlight_current_group()
	end, { buffer = input_buf, nowait = true })

	vim.api.nvim_set_option_value("cursorline", false, { win = main_win })
	vim.api.nvim_set_option_value("number", false, { win = main_win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = main_win })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.api.nvim_set_option_value("wrap", false, { win = main_win })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = main_win })

	vim.api.nvim_set_option_value("number", false, { win = input_win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = input_win })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = input_win })

	local status_buf = vim.api.nvim_create_buf(false, true)
	local status_content = "[Space] Toggle  [a] Add  [d] Delete  [w] Save  [/] Search  [q] Quit"
	local padding = math.floor((width - #status_content) / 2)
	local status_text = string.rep(" ", padding) .. status_content
	vim.api.nvim_buf_set_lines(status_buf, 0, -1, false, { status_text })
	vim.api.nvim_set_option_value("modifiable", false, { buf = status_buf })

	local status_win = vim.api.nvim_open_win(status_buf, false, {
		relative = "editor",
		width = width,
		height = 1,
		row = row + 3 + main_height + 2,
		col = col,
		style = "minimal",
		border = "single",
		focusable = false,
	})

	vim.api.nvim_set_option_value("winhl", "FloatBorder:WinSeparator", { win = status_win })

	local status_ns = vim.api.nvim_create_namespace("envim_status")
	vim.api.nvim_buf_add_highlight(status_buf, status_ns, "Comment", 0, 0, -1)

	--- Closes all popup windows
	local function close_popup()
		vim.api.nvim_win_close(input_win, true)
		vim.api.nvim_win_close(main_win, true)
		vim.api.nvim_win_close(status_win, true)
	end

	vim.keymap.set("n", "q", close_popup, { buffer = input_buf, nowait = true })
	vim.keymap.set("n", "<Esc>", close_popup, { buffer = input_buf, nowait = true })
	vim.keymap.set("i", "<Esc>", function()
		close_popup()
	end, { buffer = input_buf, nowait = true })

	vim.keymap.set("n", "q", close_popup, { buffer = buf, nowait = true })
	vim.keymap.set("n", "<Esc>", close_popup, { buffer = buf, nowait = true })

	vim.keymap.set("n", "j", function()
		smart_move(1)
		highlight_current_group()
	end, { buffer = buf, nowait = true, silent = true })
	vim.keymap.set("n", "k", function()
		smart_move(-1)
		highlight_current_group()
	end, { buffer = buf, nowait = true, silent = true })
	vim.keymap.set("n", "<Down>", function()
		smart_move(1)
		highlight_current_group()
	end, { buffer = buf, nowait = true, silent = true })
	vim.keymap.set("n", "<Up>", function()
		smart_move(-1)
		highlight_current_group()
	end, { buffer = buf, nowait = true, silent = true })

	vim.keymap.set("n", "h", "<Nop>", { buffer = buf, nowait = true })
	vim.keymap.set("n", "l", "<Nop>", { buffer = buf, nowait = true })
	vim.keymap.set("n", "<Left>", "<Nop>", { buffer = buf, nowait = true })
	vim.keymap.set("n", "<Right>", "<Nop>", { buffer = buf, nowait = true })

	vim.keymap.set("n", "gg", function()
		if #state.filtered_vars > 0 then
			local first_lines = state.env_to_lines_map[1]
			if first_lines and #first_lines > 0 then
				vim.api.nvim_win_set_cursor(vim.api.nvim_get_current_win(), { first_lines[1], 0 })
				highlight_current_group()
			end
		end
	end, { buffer = buf, nowait = true, silent = true })
	vim.keymap.set("n", "G", function()
		local last_idx = #state.filtered_vars
		if last_idx > 0 then
			local last_lines = state.env_to_lines_map[last_idx]
			if last_lines and #last_lines > 0 then
				vim.api.nvim_win_set_cursor(vim.api.nvim_get_current_win(), { last_lines[1], 0 })
				highlight_current_group()
			end
		end
	end, { buffer = buf, nowait = true, silent = true })

	vim.keymap.set("n", "<C-d>", function()
		vim.cmd("normal! \x04")
		local win = vim.api.nvim_get_current_win()
		local cursor = vim.api.nvim_win_get_cursor(win)
		local env_idx = state.line_to_env_map[cursor[1]]
		if env_idx then
			local lines = state.env_to_lines_map[env_idx]
			if lines then
				vim.api.nvim_win_set_cursor(win, { lines[1], 0 })
			end
		end
		highlight_current_group()
	end, { buffer = buf, nowait = true, silent = true })
	vim.keymap.set("n", "<C-u>", function()
		vim.cmd("normal! \x15")
		local win = vim.api.nvim_get_current_win()
		local cursor = vim.api.nvim_win_get_cursor(win)
		local env_idx = state.line_to_env_map[cursor[1]]
		if env_idx then
			local lines = state.env_to_lines_map[env_idx]
			if lines then
				vim.api.nvim_win_set_cursor(win, { lines[1], 0 })
			end
		end
		highlight_current_group()
	end, { buffer = buf, nowait = true, silent = true })

	vim.keymap.set("n", "<Space>", toggle_comment, { buffer = buf, nowait = true, silent = true })

	vim.keymap.set("n", "w", save_changes, { buffer = buf, nowait = true })

	vim.keymap.set("n", "a", add_variable, { buffer = buf, nowait = true })

	vim.keymap.set("n", "d", delete_variable, { buffer = buf, nowait = true })

	vim.keymap.set("n", "<Tab>", function()
		vim.api.nvim_set_current_win(input_win)
		vim.cmd("startinsert")
		local ns_id = vim.api.nvim_create_namespace("envim_group_highlight")
		vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
	end, { buffer = buf, nowait = true })

	vim.keymap.set("n", "/", function()
		vim.api.nvim_set_current_win(input_win)
		vim.cmd("startinsert")
		local ns_id = vim.api.nvim_create_namespace("envim_group_highlight")
		vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
	end, { buffer = buf, nowait = true })

	vim.api.nvim_create_autocmd("CursorMoved", {
		buffer = buf,
		callback = function()
			local win = vim.api.nvim_get_current_win()
			if win == main_win then
				local cursor = vim.api.nvim_win_get_cursor(win)
				if cursor[2] ~= 0 then
					vim.api.nvim_win_set_cursor(win, { cursor[1], 0 })
				end
				highlight_current_group()
			end
		end,
	})

	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = buf,
		callback = function()
			local ns_id = vim.api.nvim_create_namespace("envim_group_highlight")
			vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
		end,
	})

	vim.api.nvim_create_autocmd("WinEnter", {
		buffer = buf,
		callback = function()
			highlight_current_group()
		end,
	})

	vim.schedule(function()
		if #state.filtered_vars > 0 then
			local first_lines = state.env_to_lines_map[1]
			if first_lines and #first_lines > 0 then
				vim.api.nvim_win_set_cursor(main_win, { first_lines[1], 0 })
				highlight_current_group()
			end
		end
	end)
end

return M

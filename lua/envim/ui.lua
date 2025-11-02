local M = {}

function M.show_popup(env_vars, config, filepath)
	-- Store state
	local state = {
		all_env_vars = env_vars,
		filtered_vars = env_vars,
		search_query = "",
		filepath = filepath,
		line_to_env_map = {}, -- Maps display line numbers to env var indices
		env_to_lines_map = {}, -- Maps env var index to its lines (label + env line)
	}

	-- Create main buffer for env variables
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_option_value("filetype", "sh", { buf = buf })

	-- Create input buffer for search
	local input_buf = vim.api.nvim_create_buf(false, true)
	-- Function to render the env list
	local function render_list()
		-- Temporarily make buffer modifiable
		vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

		local lines = {}
		state.line_to_env_map = {}
		state.env_to_lines_map = {}

		for env_idx, env in ipairs(state.filtered_vars) do
			local env_lines = {}

			-- Add label line if present (as a comment)
			if env.label then
				table.insert(lines, "# " .. env.label)
				state.line_to_env_map[#lines] = env_idx
				table.insert(env_lines, #lines)
			end

			-- Add the env var line exactly as it appears in .env file (for proper syntax highlighting)
			local line
			if env.commented then
				line = string.format("# %s=%s", env.key, env.value)
			else
				line = string.format("%s=%s", env.key, env.value)
			end
			table.insert(lines, line)
			state.line_to_env_map[#lines] = env_idx
			table.insert(env_lines, #lines)

			-- Store which lines belong to this env var
			state.env_to_lines_map[env_idx] = env_lines
		end

		if #lines == 0 then
			lines = { "No matches found..." }
		end

		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

		-- Add green dot indicators using virtual text (doesn't interfere with syntax highlighting)
		local ns_id = vim.api.nvim_create_namespace("envim_indicators")
		vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

		local line_idx = 0
		for env_idx, env in ipairs(state.filtered_vars) do
			-- Skip label lines
			if env.label then
				line_idx = line_idx + 1
			end

			-- Add green dot as virtual text for active variables
			if not env.commented then
				vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, 0, {
					virt_text = { { "● ", "Function" } },
					virt_text_pos = "inline",
				})
			end
			line_idx = line_idx + 1
		end

		-- Make buffer non-modifiable again
		vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	end

	-- Function to filter based on search
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

	-- Function to highlight all lines in the current env group
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
					-- Add a subtle background highlight for the entire group
					vim.api.nvim_buf_add_highlight(buf, ns_id, "CursorLine", line_num - 1, 0, -1)
				end
			end
		end
	end

	-- Function to toggle comment on current line
	local function toggle_comment()
		local win = vim.api.nvim_get_current_win()
		local cursor = vim.api.nvim_win_get_cursor(win)
		local line_num = cursor[1]

		-- Get the env index from the line mapping
		local env_idx = state.line_to_env_map[line_num]

		if env_idx then
			local env = state.filtered_vars[env_idx]
			env.commented = not env.commented
			render_list()

			-- Move to first line of the group and re-highlight
			local group_lines = state.env_to_lines_map[env_idx]
			if group_lines and #group_lines > 0 then
				vim.api.nvim_win_set_cursor(win, { group_lines[1], 0 })
			end
			highlight_current_group()
		end
	end

	-- Function to move to next/previous env var group
	local function smart_move(direction)
		local win = vim.api.nvim_get_current_win()
		local cursor = vim.api.nvim_win_get_cursor(win)

		-- Get current env index
		local current_env_idx = state.line_to_env_map[cursor[1]]
		if not current_env_idx then
			return
		end

		-- Get next env index
		local next_env_idx = current_env_idx + direction

		-- Check if next env exists
		if next_env_idx >= 1 and next_env_idx <= #state.filtered_vars then
			local next_lines = state.env_to_lines_map[next_env_idx]
			if next_lines and #next_lines > 0 then
				-- Move to first line of the group (label if exists, otherwise env var line)
				vim.api.nvim_win_set_cursor(win, { next_lines[1], 0 })
			end
		end
	end

	-- Function to save changes to file
	local function save_changes()
		local parser = require("envim.parser")
		local success, err = parser.save_env_file(filepath, state.all_env_vars)

		if success then
			vim.notify("Saved changes to " .. filepath, vim.log.levels.INFO)
		else
			vim.notify("Error saving: " .. (err or "Unknown error"), vim.log.levels.ERROR)
		end
	end

	-- Calculate dimensions
	local width = config.window_width or 80
	local max_height = config.window_height or 20
	local total_height = math.min(#env_vars + 10, max_height) -- Extra space for borders
	local row = math.floor((vim.o.lines - total_height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	-- Input window (search bar at top) - height 1 + 2 for borders = 3 total
	local input_opts = {
		relative = "editor",
		width = width,
		height = 1,
		row = row,
		col = col,
		style = "minimal",
		border = "single",
	}

	-- Main window (env list below search)
	local main_height = math.max(10, total_height - 8) -- Reserve space for input, status, borders
	local main_opts = {
		relative = "editor",
		width = width,
		height = main_height,
		row = row + 3, -- Input takes 3 rows (1 content + 2 borders)
		col = col,
		style = "minimal",
		border = "single",
	}

	-- Create windows
	local input_win = vim.api.nvim_open_win(input_buf, true, input_opts)
	local main_win = vim.api.nvim_open_win(buf, false, main_opts)

	-- Set border highlight to use WinSeparator for thin borders
	vim.api.nvim_set_option_value("winhl", "FloatBorder:WinSeparator", { win = input_win })
	vim.api.nvim_set_option_value("winhl", "FloatBorder:WinSeparator", { win = main_win })


	-- Disable autocomplete in search input
	vim.api.nvim_set_option_value("complete", "", { buf = input_buf })
	vim.api.nvim_set_option_value("completeopt", "", { buf = input_buf })
	vim.api.nvim_set_option_value("completefunc", "", { buf = input_buf })
	vim.api.nvim_set_option_value("omnifunc", "", { buf = input_buf })
	vim.api.nvim_buf_set_var(input_buf, "cmp_enabled", false)

	-- Disable nvim-cmp if it's loaded
	local ok, cmp = pcall(require, "cmp")
	if ok then
		cmp.setup.buffer({
			enabled = false,
		})
	end

	-- Disable all insert mode completion keybindings for this buffer
	vim.keymap.set("i", "<C-n>", "<Nop>", { buffer = input_buf, nowait = true })
	vim.keymap.set("i", "<C-p>", "<Nop>", { buffer = input_buf, nowait = true })
	vim.keymap.set("i", "<C-x><C-o>", "<Nop>", { buffer = input_buf, nowait = true })
	vim.keymap.set("i", "<C-x><C-n>", "<Nop>", { buffer = input_buf, nowait = true })
	vim.keymap.set("i", "<C-x><C-p>", "<Nop>", { buffer = input_buf, nowait = true })
	vim.keymap.set("i", "<C-x><C-l>", "<Nop>", { buffer = input_buf, nowait = true })
	vim.keymap.set("i", "<C-x><C-f>", "<Nop>", { buffer = input_buf, nowait = true })

	-- Setup search input with placeholder
	local placeholder_text = "Search environment variables..."
	local placeholder_ns = vim.api.nvim_create_namespace("envim_placeholder")

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

	local function clear_placeholder()
		vim.api.nvim_buf_clear_namespace(input_buf, placeholder_ns, 0, -1)
	end

	-- Initialize buffer with empty line
	vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { "" })

	-- Close any popup menu that appears
	vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged", "InsertCharPre" }, {
		buffer = input_buf,
		callback = function()
			if vim.fn.pumvisible() == 1 then
				vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<C-e>", true, false, true), "n")
			end
		end,
	})

	-- Update search on every keystroke and manage placeholder
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = input_buf,
		callback = function()
			local line = vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1] or ""
			if line == "" then
				show_placeholder()
			else
				clear_placeholder()
			end
			update_search(line)
		end,
	})

	-- Show placeholder when entering buffer if empty
	vim.api.nvim_create_autocmd({ "BufEnter", "InsertLeave" }, {
		buffer = input_buf,
		callback = function()
			show_placeholder()
		end,
	})

	-- Show placeholder initially
	vim.schedule(function()
		show_placeholder()
		-- Start in insert mode for typing
		vim.cmd("startinsert")
	end)

	-- Initial render
	render_list()

	-- Keymaps for input buffer will be set after close_popup is defined

	-- Switch to main window with Tab
	vim.keymap.set("i", "<Tab>", function()
		vim.api.nvim_set_current_win(main_win)
		vim.cmd("stopinsert")
		highlight_current_group()
	end, { buffer = input_buf, nowait = true })

	-- Set buffer options for better block navigation
	vim.api.nvim_set_option_value("cursorline", false, { win = main_win }) -- We use custom highlighting
	vim.api.nvim_set_option_value("number", false, { win = main_win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = main_win })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.api.nvim_set_option_value("wrap", false, { win = main_win })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = main_win })

	-- Set input window options
	vim.api.nvim_set_option_value("number", false, { win = input_win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = input_win })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = input_win })

	-- Add status line at the bottom showing keybindings
	local status_buf = vim.api.nvim_create_buf(false, true)
	local status_content = "[Space] Toggle  [w] Save  [/] Search  [q] Quit"
	-- Center the status text
	local padding = math.floor((width - #status_content) / 2)
	local status_text = string.rep(" ", padding) .. status_content
	vim.api.nvim_buf_set_lines(status_buf, 0, -1, false, { status_text })
	vim.api.nvim_set_option_value("modifiable", false, { buf = status_buf })

	local status_win = vim.api.nvim_open_win(status_buf, false, {
		relative = "editor",
		width = width,
		height = 1,
		row = row + 3 + main_height + 2, -- Input (3) + main window content + main borders (2)
		col = col,
		style = "minimal",
		border = "single",
		focusable = false,
	})

	-- Set border highlight for status window
	vim.api.nvim_set_option_value("winhl", "FloatBorder:WinSeparator", { win = status_win })

	-- Highlight status line with a dimmer look
	local status_ns = vim.api.nvim_create_namespace("envim_status")
	vim.api.nvim_buf_add_highlight(status_buf, status_ns, "Comment", 0, 0, -1)

	-- Close function
	local function close_popup()
		vim.api.nvim_win_close(input_win, true)
		vim.api.nvim_win_close(main_win, true)
		vim.api.nvim_win_close(status_win, true)
	end

	-- Keymaps for input buffer
	vim.keymap.set("n", "q", close_popup, { buffer = input_buf, nowait = true })
	vim.keymap.set("n", "<Esc>", close_popup, { buffer = input_buf, nowait = true })
	vim.keymap.set("i", "<Esc>", function()
		close_popup()
	end, { buffer = input_buf, nowait = true })

	-- Keymaps for main buffer
	vim.keymap.set("n", "q", close_popup, { buffer = buf, nowait = true })
	vim.keymap.set("n", "<Esc>", close_popup, { buffer = buf, nowait = true })

	-- Block-based navigation (j/k moves between env groups)
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

	-- Disable horizontal movement
	vim.keymap.set("n", "h", "<Nop>", { buffer = buf, nowait = true })
	vim.keymap.set("n", "l", "<Nop>", { buffer = buf, nowait = true })
	vim.keymap.set("n", "<Left>", "<Nop>", { buffer = buf, nowait = true })
	vim.keymap.set("n", "<Right>", "<Nop>", { buffer = buf, nowait = true })

	-- Jump to first/last with g and G
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

	-- Page up/down (with smart positioning)
	vim.keymap.set("n", "<C-d>", function()
		vim.cmd("normal! \x04") -- Ctrl-D
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
		vim.cmd("normal! \x15") -- Ctrl-U
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

	-- Toggle comment with space
	vim.keymap.set("n", "<Space>", toggle_comment, { buffer = buf, nowait = true, silent = true })

	-- Save changes with 'w'
	vim.keymap.set("n", "w", save_changes, { buffer = buf, nowait = true })

	-- Switch back to search with Tab or /
	vim.keymap.set("n", "<Tab>", function()
		vim.api.nvim_set_current_win(input_win)
		vim.cmd("startinsert")
		-- Clear group highlighting when switching away
		local ns_id = vim.api.nvim_create_namespace("envim_group_highlight")
		vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
	end, { buffer = buf, nowait = true })

	vim.keymap.set("n", "/", function()
		vim.api.nvim_set_current_win(input_win)
		vim.cmd("startinsert")
		-- Clear group highlighting when switching away
		local ns_id = vim.api.nvim_create_namespace("envim_group_highlight")
		vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
	end, { buffer = buf, nowait = true })

	-- Keep cursor at column 0 and update group highlighting
	vim.api.nvim_create_autocmd("CursorMoved", {
		buffer = buf,
		callback = function()
			local win = vim.api.nvim_get_current_win()
			-- Only apply if we're in the main window
			if win == main_win then
				local cursor = vim.api.nvim_win_get_cursor(win)
				if cursor[2] ~= 0 then
					vim.api.nvim_win_set_cursor(win, { cursor[1], 0 })
				end
				highlight_current_group()
			end
		end,
	})

	-- Clear highlighting when leaving the main window
	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = buf,
		callback = function()
			local ns_id = vim.api.nvim_create_namespace("envim_group_highlight")
			vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
		end,
	})

	-- Restore highlighting when entering the main window
	vim.api.nvim_create_autocmd("WinEnter", {
		buffer = buf,
		callback = function()
			highlight_current_group()
		end,
	})

	-- Ensure cursor starts on first line of first group
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

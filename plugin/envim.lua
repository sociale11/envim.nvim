vim.api.nvim_create_user_command("Envim", function()
	require("envim").open()
end, {})

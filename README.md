# envim.nvim

A Neovim plugin for managing `.env` files.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'sociale/envim.nvim',
  
  config = function()
    require('envim').setup()
  end,
 
  keys = {
    { "<leader>en", "<cmd>Envim<cr>", desc = "Envim" },
  },
}
```


## Usage

Run `:Envim` to open the interface.

### Keybindings

**Search window:**
- `Tab` - Switch to variable list
- `Esc` - Close

**Variable list:**
- `j/k` - Navigate between variables
- `Space` - Toggle variable on/off (comment/uncomment)
- `w` - Save changes to file
- `/` or `Tab` - Switch to search
- `q` or `Esc` - Close

## Configuration

Default settings:

```lua
require('envim').setup({
  env_file = '.env',        -- File to read
  window_width = 150,       -- Popup width
  window_height = 100,      -- Popup height
})
```

### Screenshots
![Envim Interface](~/Pictures/envim.png)

## License

MIT

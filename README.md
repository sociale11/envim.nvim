# envim.nvim

A Neovim plugin for managing `.env` files.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'sociale11/envim.nvim',
  
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
- `a` - Add new variable
- `d` - Delete current variable
- `w` - Save changes to file
- `e` - Switch to a different .env file
- `/` or `Tab` - Switch to search
- `q` or `Esc` - Close

## Configuration

The plugin automatically scans for `.env` files in this order:
1. `.env`
2. `.env.local`
3. `.env.development`
4. `.env.production`
5. `.env.test`

When multiple files are found, you'll be prompted to choose one. Your selection is remembered for the current Neovim session. Use `e` to switch between files.

### Screenshots
<img width="1308" height="464" alt="envim" src="https://github.com/user-attachments/assets/f4ff6fc5-04cc-4427-a7f2-27a12bf73544" />

## License

MIT

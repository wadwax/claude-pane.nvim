# claude-pane.nvim

A Neovim plugin that provides a toggleable sidebar for interacting with Claude AI directly within your editor.

## Features

- 🚀 **Toggle sidebar** - Quick access to Claude AI with `<C-t>`
- 💬 **Terminal integration** - Full terminal functionality for Claude CLI
- 🔄 **Persistent sessions** - Chat history preserved between toggles
- ⌨️ **Smart keybindings** - Intuitive navigation and control
- 🎯 **Auto-focus** - Opens ready to chat with insert mode enabled
- 🔧 **Configurable** - Customize width and position

## Requirements

- Neovim >= 0.8
- [Claude CLI](https://github.com/anthropics/claude-cli) installed and in PATH
- `ANTHROPIC_API_KEY` environment variable set

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "your-username/claude-pane.nvim",
  config = function()
    require("claude-pane").setup({
      width = 60,        -- Width of the sidebar
      position = "right" -- Position: "left" or "right"
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "your-username/claude-pane.nvim",
  config = function()
    require("claude-pane").setup()
  end
}
```

## Setup

1. **Install Claude CLI**:
   ```bash
   # Follow installation instructions at:
   # https://github.com/anthropics/claude-cli
   ```

2. **Set your API key**:
   ```bash
   export ANTHROPIC_API_KEY="your-api-key-here"
   ```

   Or add to your shell profile (`.zshrc`, `.bashrc`, etc.)

## Keymaps

Add these keymaps to your Neovim configuration:

```lua
-- Toggle Claude pane
vim.keymap.set('n', '<C-t>', '<cmd>lua require("claude-pane").toggle()<CR>', { silent = true })

-- Focus Claude pane (opens if closed)
vim.keymap.set('n', '<leader>cc', '<cmd>lua require("claude-pane").focus()<CR>', { silent = true })
```

## Usage

### Basic Usage

1. **Open Claude pane**: Press `<C-t>` - opens on the right side and enters insert mode
2. **Chat with Claude**: Type your message and press `<Enter>` to send
3. **Close pane**: Press `<C-t>` or `<Esc><Esc>` to close and return to editor
4. **Navigate**: Use `<C-h>`, `<C-j>`, `<C-k>`, `<C-l>` to move between windows

### Keybindings

| Mode | Key | Action |
|------|-----|--------|
| Normal | `<C-t>` | Toggle Claude pane |
| Normal | `<leader>cc` | Focus Claude pane |
| Terminal | `<C-t>` | Close Claude pane |
| Terminal | `<Esc><Esc>` | Close Claude pane |
| Terminal | `<C-h>` | Navigate to left window |
| Terminal | `<C-l>` | Navigate to right window |
| Terminal | `<C-j>` | Navigate to bottom window |
| Terminal | `<C-k>` | Navigate to top window |

## Configuration

Default configuration:

```lua
require("claude-pane").setup({
  width = 60,        -- Sidebar width in columns
  position = "right" -- Sidebar position: "left" or "right"
})
```

## API

```lua
local claude_pane = require("claude-pane")

-- Toggle the Claude pane
claude_pane.toggle()

-- Focus the Claude pane (opens if closed, enters insert mode)
claude_pane.focus()

-- Setup with custom options
claude_pane.setup({
  width = 80,
  position = "left"
})
```

## Troubleshooting

### "claude command not found"
- Install Claude CLI following the [official instructions](https://github.com/anthropics/claude-cli)
- Ensure `claude` is in your PATH

### "ANTHROPIC_API_KEY environment variable not found"
- Set your API key: `export ANTHROPIC_API_KEY="your-key"`
- Add to your shell profile for persistence
- Restart your terminal/Neovim

### Navigation not working
- Ensure you have [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator) installed for seamless navigation
- Or use default vim window commands: `<C-w>h`, `<C-w>l`, etc.

## Similar Plugins

- [alpha-nvim](https://github.com/goolord/alpha-nvim) - Neovim greeter
- [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) - Terminal management

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) file for details.
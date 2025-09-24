local M = {}

-- State management
local state = {
  buf = nil,
  win = nil,
  is_open = false,
  claude_job_id = nil,
}

-- Configuration
local config = {
  width = 60,
  height = "80%", -- percentage of editor height or absolute number
  position = "right",
  auto_refresh = true,
  refresh_timer_interval = 1000, -- milliseconds
}

-- Set up highlight groups for darker background
local function setup_highlights()
  -- Get current Normal background
  local normal_bg = vim.fn.synIDattr(vim.fn.hlID("Normal"), "bg")

  -- If no background is set, use a default dark color
  if normal_bg == "" or normal_bg == nil then
    normal_bg = "#1e1e1e"  -- Default dark background
  end

  -- Create a darker version of the background
  local function darken_color(hex_color, factor)
    factor = factor or 0.8  -- Default darkening factor

    -- Remove # if present
    hex_color = hex_color:gsub("^#", "")

    -- Convert hex to RGB
    local r = tonumber(hex_color:sub(1, 2), 16) or 30
    local g = tonumber(hex_color:sub(3, 4), 16) or 30
    local b = tonumber(hex_color:sub(5, 6), 16) or 30

    -- Darken each component
    r = math.floor(r * factor)
    g = math.floor(g * factor)
    b = math.floor(b * factor)

    -- Convert back to hex
    return string.format("#%02x%02x%02x", r, g, b)
  end

  local darker_bg = darken_color(normal_bg, 0.7)

  -- Set up Claude pane specific highlight groups
  vim.api.nvim_set_hl(0, "ClaudePaneNormal", { bg = darker_bg })
  vim.api.nvim_set_hl(0, "ClaudePaneNormalNC", { bg = darker_bg })
end

-- File refresh state
local refresh_state = {
  timer = nil,
  original_updatetime = nil,
}

-- Check if claude command is available
local function claude_available()
  local handle = io.popen("which claude")
  local result = handle:read("*a")
  handle:close()
  return result and result ~= ""
end

-- Check if API key is available
local function api_key_available()
  return os.getenv("ANTHROPIC_API_KEY") ~= nil and os.getenv("ANTHROPIC_API_KEY") ~= ""
end

-- Calculate window dimensions
local function calculate_dimension(value, total)
  if type(value) == "string" and value:match("%%$") then
    -- Handle percentage values like "80%"
    local percent = tonumber(value:match("(%d+)%%"))
    return math.floor(total * percent / 100)
  else
    -- Handle absolute values
    return tonumber(value) or total
  end
end

-- Auto-refresh functionality
local function setup_auto_refresh()
  if not config.auto_refresh then
    return
  end

  -- Enable autoread
  vim.o.autoread = true

  -- Store original updatetime
  if not refresh_state.original_updatetime then
    refresh_state.original_updatetime = vim.o.updatetime
  end

  -- Set faster updatetime when Claude pane is open
  vim.o.updatetime = math.min(vim.o.updatetime, 1000)

  -- Set up autocommands for file refresh
  vim.api.nvim_create_autocmd({"CursorHold", "CursorHoldI", "FocusGained", "BufEnter", "WinEnter"}, {
    group = vim.api.nvim_create_augroup("ClaudePaneAutoRefresh", { clear = true }),
    callback = function()
      if state.is_open then
        vim.cmd('checktime')
      end
    end,
  })

  -- Optional: Set up periodic timer for more aggressive checking
  if config.refresh_timer_interval > 0 then
    if refresh_state.timer then
      refresh_state.timer:stop()
    end

    refresh_state.timer = vim.loop.new_timer()
    refresh_state.timer:start(config.refresh_timer_interval, config.refresh_timer_interval, vim.schedule_wrap(function()
      if state.is_open then
        vim.cmd('silent! checktime')
      end
    end))
  end
end

-- Clean up auto-refresh
local function cleanup_auto_refresh()
  if refresh_state.timer then
    refresh_state.timer:stop()
    refresh_state.timer:close()
    refresh_state.timer = nil
  end

  -- Restore original updatetime
  if refresh_state.original_updatetime then
    vim.o.updatetime = refresh_state.original_updatetime
    refresh_state.original_updatetime = nil
  end

  -- Clear autocommands
  pcall(vim.api.nvim_del_augroup_by_name, "ClaudePaneAutoRefresh")
end

-- Create or get the claude buffer
local function get_or_create_buffer()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    return state.buf
  end

  -- Create new buffer for terminal
  state.buf = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.api.nvim_buf_set_option(state.buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(state.buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(state.buf, 'bufhidden', 'hide')
  vim.api.nvim_buf_set_name(state.buf, 'Claude')

  return state.buf
end

-- Start claude process
local function start_claude()
  if state.claude_job_id then
    -- Claude is already running
    return
  end

  if not api_key_available() then
    -- Show API key error message
    state.claude_job_id = vim.fn.termopen("echo 'Error: ANTHROPIC_API_KEY environment variable not found.'; echo 'Please set your API key: export ANTHROPIC_API_KEY=\"your-key-here\"'; echo 'Or add it to your ~/.api_keys file (sourced by .zprofile)'", {
      cwd = vim.fn.getcwd(),
      on_exit = function(job_id, exit_code, event_type)
        state.claude_job_id = nil
      end
    })
    return
  end

  if not claude_available() then
    -- Show error message in terminal
    state.claude_job_id = vim.fn.termopen("echo 'Error: claude command not found in PATH. Please install Claude CLI first.'", {
      cwd = vim.fn.getcwd(),
      on_exit = function(job_id, exit_code, event_type)
        state.claude_job_id = nil
      end
    })
    return
  end

  -- Start claude process
  state.claude_job_id = vim.fn.termopen("claude", {
    cwd = vim.fn.getcwd(),
    on_exit = function(job_id, exit_code, event_type)
      state.claude_job_id = nil
    end
  })
end

-- Create window
local function create_window()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    return state.win
  end

  local buf = get_or_create_buffer()

  -- Use vim split instead of floating window for better navigation
  if config.position == "right" then
    vim.cmd("rightbelow vertical split")
  else
    vim.cmd("leftabove vertical split")
  end

  -- Get the new window
  state.win = vim.api.nvim_get_current_win()

  -- Set the buffer in the new window
  vim.api.nvim_win_set_buf(state.win, buf)

  -- Calculate and set dynamic window dimensions
  local editor_width = vim.o.columns

  local window_width = calculate_dimension(config.width, editor_width)

  vim.api.nvim_win_set_width(state.win, window_width)
  -- Don't set height for vertical splits - let it inherit from adjacent panes

  -- Set window options
  vim.api.nvim_win_set_option(state.win, 'wrap', true)
  vim.api.nvim_win_set_option(state.win, 'cursorline', true)
  vim.api.nvim_win_set_option(state.win, 'number', false)
  vim.api.nvim_win_set_option(state.win, 'relativenumber', false)

  -- Apply darker background highlighting
  setup_highlights()
  vim.api.nvim_win_set_option(state.win, 'winhighlight', 'Normal:ClaudePaneNormal,NormalNC:ClaudePaneNormalNC')

  -- Set up terminal mode keymaps for this buffer
  vim.api.nvim_buf_set_keymap(buf, 't', '<C-t>', '<C-\\><C-n>:lua require("claude-pane").toggle()<CR>', { silent = true, noremap = true })
  vim.api.nvim_buf_set_keymap(buf, 't', '<Esc><Esc>', '<C-\\><C-n>:lua require("claude-pane").toggle()<CR>', { silent = true, noremap = true })
  vim.api.nvim_buf_set_keymap(buf, 't', '<C-h>', '<C-\\><C-n><C-w>h', { silent = true, noremap = true })
  vim.api.nvim_buf_set_keymap(buf, 't', '<C-l>', '<C-\\><C-n><C-w>l', { silent = true, noremap = true })
  vim.api.nvim_buf_set_keymap(buf, 't', '<C-j>', '<C-\\><C-n><C-w>j', { silent = true, noremap = true })
  vim.api.nvim_buf_set_keymap(buf, 't', '<C-k>', '<C-\\><C-n><C-w>k', { silent = true, noremap = true })

  -- Auto-enter insert mode when entering the Claude pane window
  vim.api.nvim_create_autocmd({"BufEnter", "WinEnter"}, {
    buffer = buf,
    callback = function()
      if vim.api.nvim_get_current_win() == state.win and state.is_open then
        vim.cmd('startinsert')
      end
    end,
    group = vim.api.nvim_create_augroup("ClaudePaneInsertMode", { clear = false })
  })

  return state.win
end

-- Close the window
local function close_window()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
    state.win = nil
  end
end

-- Toggle the claude pane
function M.toggle()
  if state.is_open then
    -- Close the pane
    close_window()
    cleanup_auto_refresh()
    state.is_open = false
  else
    -- Open the pane
    create_window()

    -- Set up auto-refresh when pane opens
    setup_auto_refresh()

    -- Start claude if not already running and buffer exists
    if state.buf and vim.api.nvim_buf_is_valid(state.buf) and not state.claude_job_id then
      -- Start claude in the terminal buffer (we're already in the claude window)
      start_claude()
    end

    -- Stay in the claude pane and enter insert mode
    vim.cmd('startinsert')

    state.is_open = true
  end
end

-- Focus the claude pane
function M.focus()
  if state.is_open and state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
    -- Enter terminal insert mode
    vim.cmd('startinsert')
  else
    M.toggle()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_set_current_win(state.win)
      vim.cmd('startinsert')
    end
  end
end

-- Resize the claude pane
function M.resize(width, height)
  if not state.is_open or not state.win or not vim.api.nvim_win_is_valid(state.win) then
    vim.notify("Claude pane is not open", vim.log.levels.WARN)
    return
  end

  -- Update config if new values provided
  if width then
    config.width = width
  end
  if height then
    config.height = height
    vim.notify("Height setting ignored for vertical splits - height inherits from adjacent panes", vim.log.levels.WARN)
  end

  -- Calculate new dimensions
  local editor_width = vim.o.columns

  local window_width = calculate_dimension(config.width, editor_width)

  -- Apply new dimensions (only width for vertical splits)
  vim.api.nvim_win_set_width(state.win, window_width)

  vim.notify(string.format("Claude pane resized to width %d", window_width), vim.log.levels.INFO)
end

-- Setup function
function M.setup(opts)
  opts = opts or {}
  config = vim.tbl_extend("force", config, opts)
end

-- Helper function to get current config (for commands)
function M._get_config()
  return config
end

-- Cleanup function
function M.cleanup()
  if state.claude_job_id then
    vim.fn.jobstop(state.claude_job_id)
    state.claude_job_id = nil
  end
  close_window()
  cleanup_auto_refresh()
  -- Clean up insert mode autocmds
  pcall(vim.api.nvim_del_augroup_by_name, "ClaudePaneInsertMode")
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state.buf = nil
  state.is_open = false
end

-- Auto command to cleanup on exit
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    M.cleanup()
  end,
})

-- Auto command to refresh highlights when colorscheme changes
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    setup_highlights()
    -- Refresh window highlight if Claude pane is open
    if state.is_open and state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_set_option(state.win, 'winhighlight', 'Normal:ClaudePaneNormal,NormalNC:ClaudePaneNormalNC')
    end
  end,
})

return M
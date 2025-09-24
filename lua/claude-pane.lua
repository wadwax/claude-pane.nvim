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

local function setup_highlights()
  local neotree_normal_bg = vim.fn.synIDattr(vim.fn.hlID("NeoTreeNormal"), "bg")
  local neotree_normal_nc_bg = vim.fn.synIDattr(vim.fn.hlID("NeoTreeNormalNC"), "bg")
  local normal_bg = vim.fn.synIDattr(vim.fn.hlID("Normal"), "bg")

  local claude_bg = neotree_normal_bg ~= "" and neotree_normal_bg or normal_bg
  local claude_nc_bg = neotree_normal_nc_bg ~= "" and neotree_normal_nc_bg or normal_bg

  if claude_bg == "" or claude_bg == nil then
    claude_bg = "#1e1e1e"
  end
  if claude_nc_bg == "" or claude_nc_bg == nil then
    claude_nc_bg = "#1e1e1e"
  end

  vim.api.nvim_set_hl(0, "ClaudePaneNormal", { bg = claude_bg })
  vim.api.nvim_set_hl(0, "ClaudePaneNormalNC", { bg = claude_nc_bg })
end

-- File refresh state
local refresh_state = {
  timer = nil,
  original_updatetime = nil,
}

-- Visual selection handling functions
local function get_visual_selection()
  -- Check if we're in visual mode or just exited it
  local mode = vim.fn.mode()
  if mode == 'v' or mode == 'V' or mode == '\22' then -- \22 is visual block mode
    -- We're currently in visual mode - get selection
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    local start_line = start_pos[2]
    local end_line = end_pos[2]

    -- Get the selected lines
    local lines = vim.fn.getline(start_line, end_line)
    local selected_text = table.concat(lines, '\n')

    -- Get current file path
    local file_path = vim.fn.expand('%:p')
    local relative_path = vim.fn.expand('%:.')

    return {
      text = selected_text,
      file_path = file_path,
      relative_path = relative_path,
      start_line = start_line,
      end_line = end_line
    }
  else
    -- Check if there was a recent visual selection
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")

    -- Only use the previous selection if it's in the current buffer
    if start_pos[1] ~= 0 and end_pos[1] ~= 0 then
      local start_line = start_pos[2]
      local end_line = end_pos[2]

      -- Get the previously selected lines
      local lines = vim.fn.getline(start_line, end_line)
      local selected_text = table.concat(lines, '\n')

      -- Get current file path
      local file_path = vim.fn.expand('%:p')
      local relative_path = vim.fn.expand('%:.')

      return {
        text = selected_text,
        file_path = file_path,
        relative_path = relative_path,
        start_line = start_line,
        end_line = end_line
      }
    end
  end

  return nil
end

local function format_code_block(selection)
  if not selection or not selection.text or selection.text == '' then
    return nil
  end

  local line_range = selection.start_line == selection.end_line
    and tostring(selection.start_line)
    or selection.start_line .. ':' .. selection.end_line

  return string.format('```%s:%s\n%s\n```\n\n', selection.relative_path, line_range, selection.text)
end

local function paste_to_claude(text)
  if not text or not state.claude_job_id then
    return false
  end

  -- Send the text to the claude terminal
  vim.fn.chansend(state.claude_job_id, text)
  return true
end

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
    -- Check if there's a visual selection first
    local selection = get_visual_selection()
    local formatted_text = nil
    if selection then
      formatted_text = format_code_block(selection)
    end

    -- If there's a selection and claude is running, paste it instead of closing
    if formatted_text and state.claude_job_id then
      -- Focus the claude pane and paste the selection
      if state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_set_current_win(state.win)
      end
      paste_to_claude(formatted_text)
      vim.cmd('startinsert')
      return
    end

    -- Close the pane (only if no selection to paste)
    close_window()
    cleanup_auto_refresh()
    state.is_open = false
  else
    -- Get visual selection before opening the pane
    local selection = get_visual_selection()
    local formatted_text = nil
    if selection then
      formatted_text = format_code_block(selection)
    end

    -- Open the pane
    create_window()

    -- Set up auto-refresh when pane opens
    setup_auto_refresh()

    -- Start claude if not already running and buffer exists
    if state.buf and vim.api.nvim_buf_is_valid(state.buf) and not state.claude_job_id then
      -- Start claude in the terminal buffer (we're already in the claude window)
      start_claude()
    end

    -- If we have formatted text, paste it once claude is ready
    if formatted_text then
      -- Use vim.defer_fn to ensure the terminal is ready and claude is started
      local function try_paste()
        if state.claude_job_id then
          paste_to_claude(formatted_text)
        else
          -- If claude isn't ready yet, try again in a bit
          vim.defer_fn(try_paste, 100)
        end
      end
      vim.defer_fn(try_paste, 100)
    end

    -- Stay in the claude pane and enter insert mode
    vim.cmd('startinsert')

    state.is_open = true
  end
end

-- Focus the claude pane
function M.focus()
  if state.is_open and state.win and vim.api.nvim_win_is_valid(state.win) then
    -- Get visual selection before focusing
    local selection = get_visual_selection()
    local formatted_text = nil
    if selection then
      formatted_text = format_code_block(selection)
    end

    vim.api.nvim_set_current_win(state.win)

    -- If we have formatted text and claude is running, paste it
    if formatted_text and state.claude_job_id then
      paste_to_claude(formatted_text)
    end

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
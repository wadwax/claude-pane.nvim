-- Claude Pane plugin commands

-- Create user commands for claude-pane
vim.api.nvim_create_user_command('ClaudePaneToggle', function()
  require('claude-pane').toggle()
end, { desc = 'Toggle Claude pane' })

vim.api.nvim_create_user_command('ClaudePaneFocus', function()
  require('claude-pane').focus()
end, { desc = 'Focus Claude pane' })

vim.api.nvim_create_user_command('ClaudePaneResize', function(opts)
  local args = vim.split(opts.args, '%s+')
  local width, height

  if #args == 1 then
    -- Single argument - treat as width
    width = args[1]
  elseif #args == 2 then
    -- Two arguments - width and height
    width = args[1]
    height = args[2]
  elseif #args == 0 then
    -- No arguments - show current size
    local claude_pane = require('claude-pane')
    local config = claude_pane._get_config and claude_pane._get_config() or {}
    vim.notify(string.format("Current size: width=%s, height=%s", config.width or "60", config.height or "80%"), vim.log.levels.INFO)
    return
  else
    vim.notify("Usage: :ClaudePaneResize [width] [height]\nExamples:\n  :ClaudePaneResize 80\n  :ClaudePaneResize 80 40\n  :ClaudePaneResize 30% 90%", vim.log.levels.ERROR)
    return
  end

  require('claude-pane').resize(width, height)
end, {
  nargs = '*',
  desc = 'Resize Claude pane. Usage: :ClaudePaneResize [width] [height]',
  complete = function(ArgLead, CmdLine, CursorPos)
    -- Simple completion with common sizes
    return {'60', '80', '100', '25%', '30%', '50%', '75%', '80%', '90%'}
  end
})
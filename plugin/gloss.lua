--- Lazy-load trigger for gloss.nvim
--- Registers stub commands that load the real plugin on first use.

if vim.g.loaded_gloss then
  return
end
vim.g.loaded_gloss = true

local commands = {
  'GlossAdd',
  'GlossDelete',
  'GlossExpand',
  'GlossCollapse',
  'GlossToggle',
  'GlossNext',
  'GlossPrev',
  'GlossAttach',
}

for _, cmd in ipairs(commands) do
  vim.api.nvim_create_user_command(cmd, function(opts)
    -- Remove all stub commands
    for _, c in ipairs(commands) do
      pcall(vim.api.nvim_del_user_command, c)
    end

    -- Load the real plugin (idempotent)
    require('gloss').setup()

    -- Re-dispatch the original command
    if opts.range == 2 then
      vim.cmd(string.format('%d,%d%s %s', opts.line1, opts.line2, cmd, opts.args or ''))
    else
      vim.cmd(string.format('%s %s', cmd, opts.args or ''))
    end
  end, {
    nargs = '*',
    range = true,
    desc = 'gloss.nvim: ' .. cmd .. ' (lazy stub)',
  })
end

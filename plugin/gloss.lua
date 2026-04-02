--- Lazy-load trigger for gloss.nvim
--- Registers stub commands that load the real plugin on first use.

if vim.g.loaded_gloss then
  return
end
vim.g.loaded_gloss = true

local commands = {
  'GlossAdd',
  'GlossDelete',
  'GlossEdit',
  'GlossExpand',
  'GlossCollapse',
  'GlossToggle',
  'GlossNext',
  'GlossPrev',
  'GlossAttach',
  'GlossList',
}

for _, cmd in ipairs(commands) do
  vim.api.nvim_create_user_command(cmd, function(opts)
    -- Load the real plugin (idempotent) — before removing stubs
    -- so commands still exist if setup() fails
    require('gloss').setup()

    -- Remove all stub commands (real handlers are now registered)
    for _, c in ipairs(commands) do
      pcall(vim.api.nvim_del_user_command, c)
    end

    -- Dispatch directly to preserve visual context (visualmode(), marks)
    require('gloss.commands').dispatch(cmd, opts)
  end, {
    nargs = '*',
    range = true,
    desc = 'gloss.nvim: ' .. cmd .. ' (lazy stub)',
  })
end

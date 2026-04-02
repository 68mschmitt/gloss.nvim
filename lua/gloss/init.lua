--- gloss.nvim — Plugin entry point
--- setup() is the single entry point. Idempotent.

local M = {}

local is_setup = false

--- Initialize gloss.nvim.
--- @param opts table|nil User configuration options
function M.setup(opts)
  if is_setup then
    return
  end
  is_setup = true

  -- Merge config
  local config = require('gloss.config')
  config.setup(opts)

  -- Set up highlight groups
  local highlights = require('gloss.ui.highlights')
  highlights.setup()

  -- Load core modules
  local annotation = require('gloss.core.annotation')
  local store = require('gloss.core.store')
  local tracker = require('gloss.core.tracker')

  -- Register commands
  local commands = require('gloss.commands')
  commands.register(annotation, store, tracker)

  -- Ensure state directory exists
  local cfg = config.get()
  vim.fn.mkdir(cfg.state_dir, 'p')

  -- Set up autocommands
  local augroup = vim.api.nvim_create_augroup('gloss', { clear = true })

  -- On buffer read: load annotations and reconcile positions
  vim.api.nvim_create_autocmd('BufReadPost', {
    group = augroup,
    callback = function(ev)
      local bufnr = ev.buf
      local filepath = vim.api.nvim_buf_get_name(bufnr)
      if filepath == '' then
        return
      end

      -- Only load if a gloss file exists for this buffer
      if store.has_gloss_file(filepath) then
        store.load(bufnr, filepath)
        tracker.reconcile(bufnr, annotation)
        -- Render via commands.render_buffer so extmark IDs are tracked
        -- (enables targeted clear_one for delete/expand/collapse)
        commands.render_buffer(bufnr)
      end
    end,
  })

  -- On buffer write: sync extmark positions and persist
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = augroup,
    callback = function(ev)
      local bufnr = ev.buf
      if annotation.list(bufnr) then
        tracker.sync_from_extmarks(bufnr, annotation)
        store.save(bufnr)
      end
    end,
  })

  -- On buffer unload: clean up all in-memory state
  vim.api.nvim_create_autocmd('BufUnload', {
    group = augroup,
    callback = function(ev)
      local bufnr = ev.buf
      -- Skip scratch/float buffers (their BufUnload fires re-entrantly
      -- when float.close_all wipes the backing buffer)
      if vim.bo[bufnr].buftype ~= '' then
        return
      end
      -- Lazy-require UI modules (only needed at cleanup time)
      local float = require('gloss.ui.float')
      local cycle = require('gloss.ui.cycle')
      float.close_all(bufnr)
      annotation.clear(bufnr)
      tracker.clear(bufnr)
      store.clear(bufnr)
      cycle.clear(bufnr)
    end,
  })
end

return M

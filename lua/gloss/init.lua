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
        -- Render signs and highlights for loaded annotations
        local ns_id = vim.api.nvim_create_namespace('gloss')
        local signs = require('gloss.ui.signs')
        local hl = require('gloss.ui.highlights')
        local annotations = annotation.list(bufnr)
        if annotations then
          for _, ann in ipairs(annotations) do
            signs.place(bufnr, ns_id, ann.line_start, cfg.sign_text, cfg.sign_hl)
            hl.apply(
              bufnr,
              ns_id,
              ann.line_start,
              ann.line_end,
              ann.col_start,
              ann.col_end,
              not ann.collapsed
            )
          end
        end
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

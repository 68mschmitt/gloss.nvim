--- Command definitions and dispatch for gloss.nvim
--- Maps user-facing :Gloss* commands to core operations.

local M = {}

--- @type table<string, fun(opts: table)>
local handlers = {}

--- Register all :Gloss* commands.
--- @param annotation_mod table The gloss.core.annotation module
--- @param store_mod table The gloss.core.store module
--- @param tracker_mod table The gloss.core.tracker module
function M.register(annotation_mod, store_mod, tracker_mod)
  local cfg = require('gloss.config').get()
  local float = require('gloss.ui.float')
  local signs = require('gloss.ui.signs')
  local highlights = require('gloss.ui.highlights')
  local ns_id = vim.api.nvim_create_namespace('gloss')

  --- Render all non-collapsed annotations for a buffer.
  --- @param bufnr integer
  local function render_buffer(bufnr)
    local annotations = annotation_mod.list(bufnr)
    if not annotations then
      return
    end

    for _, ann in ipairs(annotations) do
      -- Place sign on the first line
      signs.place(bufnr, ns_id, ann.line_start, cfg.sign_text, cfg.sign_hl)

      -- Apply highlight to referenced text
      local active = not ann.collapsed
      highlights.apply(bufnr, ns_id, ann.line_start, ann.line_end, ann.col_start, ann.col_end, active)

      -- Show float if expanded
      if not ann.collapsed then
        float.open(bufnr, ann.id, ann.content, ann.line_start, cfg)
      end
    end
  end

  --- Re-render: clear everything and redraw.
  --- @param bufnr integer
  local function rerender(bufnr)
    float.close_all(bufnr)
    signs.clear_all(bufnr, ns_id)
    highlights.clear_all(bufnr, ns_id)
    render_buffer(bufnr)
  end

  -- :GlossAdd — add annotation at current location
  handlers['GlossAdd'] = function(opts)
    local bufnr = vim.api.nvim_get_current_buf()
    local mode = vim.fn.mode()
    local line_start, line_end, col_start, col_end
    local location_type

    if opts.range == 2 then
      -- Visual selection range (line-wise from command range)
      line_start = opts.line1 - 1 -- convert to 0-indexed
      line_end = opts.line2 - 1
      if line_start == line_end then
        location_type = 'line'
      else
        location_type = 'range'
      end
    else
      -- Current line
      line_start = vim.api.nvim_win_get_cursor(0)[1] - 1
      line_end = line_start
      location_type = 'line'
    end

    -- Open a scratch buffer in a split for writing the annotation
    local source_win = vim.api.nvim_get_current_win()
    vim.cmd('botright ' .. cfg.edit_height .. 'new')
    local edit_buf = vim.api.nvim_get_current_buf()

    vim.bo[edit_buf].buftype = 'acwrite'
    vim.bo[edit_buf].filetype = 'markdown'
    vim.bo[edit_buf].bufhidden = 'wipe'
    vim.bo[edit_buf].swapfile = false

    -- Set a buffer name so :w works
    vim.api.nvim_buf_set_name(edit_buf, 'gloss://new-annotation')

    -- On BufWriteCmd, capture content and create annotation
    vim.api.nvim_create_autocmd('BufWriteCmd', {
      buffer = edit_buf,
      once = true,
      callback = function()
        local lines = vim.api.nvim_buf_get_lines(edit_buf, 0, -1, false)
        local content = table.concat(lines, '\n')

        -- Trim trailing whitespace
        content = content:gsub('%s+$', '')

        if content == '' then
          vim.notify('gloss: empty annotation, cancelled', vim.log.levels.WARN)
        else
          annotation_mod.create(bufnr, {
            content = content,
            location_type = location_type,
            line_start = line_start,
            line_end = line_end,
            col_start = col_start,
            col_end = col_end,
          })
          store_mod.save(bufnr)
          rerender(bufnr)
          vim.notify('gloss: annotation added', vim.log.levels.INFO)
        end

        -- Close the edit buffer and return to source
        vim.api.nvim_buf_delete(edit_buf, { force = true })
        if vim.api.nvim_win_is_valid(source_win) then
          vim.api.nvim_set_current_win(source_win)
        end
      end,
    })
  end

  -- :GlossDelete — delete annotation under cursor
  handlers['GlossDelete'] = function(_opts)
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1

    local ann = annotation_mod.find_at(bufnr, cursor_line)
    if not ann then
      vim.notify('gloss: no annotation at cursor', vim.log.levels.WARN)
      return
    end

    annotation_mod.delete(bufnr, ann.id)
    store_mod.save(bufnr)
    rerender(bufnr)
    vim.notify('gloss: annotation deleted', vim.log.levels.INFO)
  end

  -- :GlossExpand — expand annotation under cursor
  handlers['GlossExpand'] = function(_opts)
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1

    local ann = annotation_mod.find_at(bufnr, cursor_line)
    if not ann then
      vim.notify('gloss: no annotation at cursor', vim.log.levels.WARN)
      return
    end

    annotation_mod.set_collapsed(bufnr, ann.id, false)
    rerender(bufnr)
  end

  -- :GlossCollapse — collapse annotation under cursor
  handlers['GlossCollapse'] = function(_opts)
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1

    local ann = annotation_mod.find_at(bufnr, cursor_line)
    if not ann then
      vim.notify('gloss: no annotation at cursor', vim.log.levels.WARN)
      return
    end

    annotation_mod.set_collapsed(bufnr, ann.id, true)
    rerender(bufnr)
  end

  -- :GlossToggle — toggle all annotations in buffer
  handlers['GlossToggle'] = function(_opts)
    local bufnr = vim.api.nvim_get_current_buf()
    local annotations = annotation_mod.list(bufnr)
    if not annotations or #annotations == 0 then
      vim.notify('gloss: no annotations in buffer', vim.log.levels.INFO)
      return
    end

    -- If any are expanded, collapse all; otherwise expand all
    local any_expanded = false
    for _, ann in ipairs(annotations) do
      if not ann.collapsed then
        any_expanded = true
        break
      end
    end

    for _, ann in ipairs(annotations) do
      annotation_mod.set_collapsed(bufnr, ann.id, any_expanded)
    end

    rerender(bufnr)
  end

  -- :GlossNext — cycle to next overlapping annotation
  handlers['GlossNext'] = function(_opts)
    local cycle = require('gloss.ui.cycle')
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1
    cycle.next(bufnr, cursor_line, annotation_mod, cfg, ns_id)
  end

  -- :GlossPrev — cycle to previous overlapping annotation
  handlers['GlossPrev'] = function(_opts)
    local cycle = require('gloss.ui.cycle')
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1
    cycle.prev(bufnr, cursor_line, annotation_mod, cfg, ns_id)
  end

  -- :GlossAttach — attach a gloss file to current buffer
  handlers['GlossAttach'] = function(_opts)
    local bufnr = vim.api.nvim_get_current_buf()
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    if filepath == '' then
      vim.notify('gloss: buffer has no file path', vim.log.levels.ERROR)
      return
    end

    vim.ui.select({ 'Default location', 'Custom file...' }, {
      prompt = 'Gloss file location:',
    }, function(choice)
      if not choice then
        return
      end

      if choice == 'Default location' then
        store_mod.load(bufnr, filepath)
        tracker_mod.reconcile(bufnr, annotation_mod)
        rerender(bufnr)
      else
        vim.ui.input({ prompt = 'Gloss file path: ', completion = 'file' }, function(input)
          if not input or input == '' then
            return
          end
          store_mod.load(bufnr, filepath, input)
          tracker_mod.reconcile(bufnr, annotation_mod)
          rerender(bufnr)
        end)
      end
    end)
  end

  -- Register all commands with neovim
  for cmd_name, handler in pairs(handlers) do
    vim.api.nvim_create_user_command(cmd_name, handler, {
      nargs = '*',
      range = true,
      desc = 'gloss.nvim: ' .. cmd_name,
    })
  end
end

--- Unregister all :Gloss* commands (for cleanup/testing).
function M.unregister()
  for cmd_name, _ in pairs(handlers) do
    pcall(vim.api.nvim_del_user_command, cmd_name)
  end
  handlers = {}
end

return M

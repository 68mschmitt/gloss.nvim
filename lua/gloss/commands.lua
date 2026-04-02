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
  local ns_id = require('gloss.config').ns.gloss

  --- Render a single annotation (sign + highlight + float if expanded).
  --- Stores rendering extmark IDs on the annotation for targeted cleanup.
  --- @param bufnr integer
  --- @param ann gloss.Annotation
  local function render_one(bufnr, ann)
    -- Place sign on the first line
    ann._sign_extmark = signs.place(bufnr, ns_id, ann.line_start, cfg.sign_text, cfg.sign_hl)

    -- Apply highlight to referenced text
    local active = not ann.collapsed
    ann._hl_extmark = highlights.apply(
      bufnr,
      ns_id,
      ann.line_start,
      ann.line_end,
      ann.col_start,
      ann.col_end,
      active
    )

    -- Show float if expanded
    if not ann.collapsed then
      float.open(bufnr, ann.id, ann.content, ann.line_start, cfg)
    end
  end

  --- Clear rendering for a single annotation.
  --- @param bufnr integer
  --- @param ann gloss.Annotation
  local function clear_one(bufnr, ann)
    if ann._sign_extmark then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, ns_id, ann._sign_extmark)
      ann._sign_extmark = nil
    end
    if ann._hl_extmark then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, ns_id, ann._hl_extmark)
      ann._hl_extmark = nil
    end
    float.close_by_annotation(bufnr, ann.id)
  end

  --- Render all annotations for a buffer.
  --- @param bufnr integer
  local function render_buffer(bufnr)
    local annotations = annotation_mod.list(bufnr)
    if not annotations then
      return
    end

    for _, ann in ipairs(annotations) do
      render_one(bufnr, ann)
    end
  end

  -- Expose render_buffer for use by init.lua (BufReadPost)
  M.render_buffer = render_buffer

  --- Full re-render: clear everything and redraw.
  --- Used for bulk operations (toggle all, attach).
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
    local line_start, line_end, col_start, col_end
    local location_type

    if opts.range == 2 then
      -- Visual selection — check visual mode for charwise vs linewise
      local vmode = vim.fn.visualmode()
      line_start = opts.line1 - 1 -- convert to 0-indexed
      line_end = opts.line2 - 1

      if vmode == 'v' and line_start == line_end then
        -- Charwise visual on a single line: word-level annotation
        local start_pos = vim.fn.getpos("'<")
        local end_pos = vim.fn.getpos("'>")
        col_start = start_pos[3] - 1 -- 0-indexed byte offset

        -- Compute exclusive end accounting for multi-byte characters
        local line_text = vim.api.nvim_buf_get_lines(bufnr, line_end, line_end + 1, false)[1] or ''
        local end_byte = math.min(end_pos[3] - 1, #line_text - 1) -- clamp for $-inclusive
        local char_idx = vim.fn.charidx(line_text, end_byte)
        if char_idx < 0 then
          col_end = #line_text
        else
          local next_byte = vim.fn.byteidx(line_text, char_idx + 1)
          col_end = next_byte == -1 and #line_text or next_byte
        end

        location_type = 'word'
      elseif vmode == 'v' and line_start ~= line_end then
        -- Charwise visual across lines: coerce to line range
        vim.notify(
          'gloss: multi-line charwise selection coerced to line range',
          vim.log.levels.INFO
        )
        location_type = 'range'
      elseif line_start == line_end then
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

    -- Set a unique buffer name so :w works (avoid collisions with concurrent edits)
    vim.api.nvim_buf_set_name(edit_buf, 'gloss://new-' .. vim.uv.hrtime())

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
          local ann = annotation_mod.create(bufnr, {
            content = content,
            location_type = location_type,
            line_start = line_start,
            line_end = line_end,
            col_start = col_start,
            col_end = col_end,
          })
          store_mod.save(bufnr)
          render_one(bufnr, ann)
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

    -- Clear rendering before deleting the annotation data
    clear_one(bufnr, ann)
    annotation_mod.delete(bufnr, ann.id)
    store_mod.save(bufnr)
    vim.notify('gloss: annotation deleted', vim.log.levels.INFO)
  end

  -- :GlossEdit — edit annotation under cursor
  handlers['GlossEdit'] = function(_opts)
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1

    local ann = annotation_mod.find_at(bufnr, cursor_line)
    if not ann then
      vim.notify('gloss: no annotation at cursor', vim.log.levels.WARN)
      return
    end

    -- Open a scratch buffer pre-populated with existing content
    local source_win = vim.api.nvim_get_current_win()
    vim.cmd('botright ' .. cfg.edit_height .. 'new')
    local edit_buf = vim.api.nvim_get_current_buf()

    vim.bo[edit_buf].buftype = 'acwrite'
    vim.bo[edit_buf].filetype = 'markdown'
    vim.bo[edit_buf].bufhidden = 'wipe'
    vim.bo[edit_buf].swapfile = false

    vim.api.nvim_buf_set_name(edit_buf, 'gloss://edit-' .. vim.uv.hrtime())

    -- Pre-populate with existing content
    local existing_lines = vim.split(ann.content, '\n', { plain = true })
    vim.api.nvim_buf_set_lines(edit_buf, 0, -1, false, existing_lines)
    vim.bo[edit_buf].modified = false

    -- Capture annotation ID to avoid closure over mutable ann
    local ann_id = ann.id

    vim.api.nvim_create_autocmd('BufWriteCmd', {
      buffer = edit_buf,
      once = true,
      callback = function()
        local lines = vim.api.nvim_buf_get_lines(edit_buf, 0, -1, false)
        local content = table.concat(lines, '\n')
        content = content:gsub('%s+$', '')

        if content == '' then
          vim.notify('gloss: empty content, edit cancelled', vim.log.levels.WARN)
        else
          -- Re-find the annotation in case buffer state changed
          local target = annotation_mod.find_by_id(bufnr, ann_id)
          if target then
            annotation_mod.update_content(bufnr, ann_id, content)
            store_mod.save(bufnr)
            clear_one(bufnr, target)
            render_one(bufnr, target)
            vim.notify('gloss: annotation updated', vim.log.levels.INFO)
          else
            vim.notify('gloss: annotation no longer exists', vim.log.levels.ERROR)
          end
        end

        vim.api.nvim_buf_delete(edit_buf, { force = true })
        if vim.api.nvim_win_is_valid(source_win) then
          vim.api.nvim_set_current_win(source_win)
        end
      end,
    })
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
    clear_one(bufnr, ann)
    render_one(bufnr, ann)
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
    clear_one(bufnr, ann)
    render_one(bufnr, ann)
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
  -- Accepts optional file path argument: :GlossAttach /path/to/file.json
  handlers['GlossAttach'] = function(opts)
    local bufnr = vim.api.nvim_get_current_buf()
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    if filepath == '' then
      vim.notify('gloss: buffer has no file path', vim.log.levels.ERROR)
      return
    end

    local args = vim.trim(opts.args or '')

    if args ~= '' then
      -- Direct path provided as argument — resolve to absolute
      local resolved = vim.fn.fnamemodify(args, ':p')
      store_mod.load(bufnr, filepath, resolved)
      tracker_mod.reconcile(bufnr, annotation_mod)
      rerender(bufnr)
      return
    end

    -- Interactive: select default or custom
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

  -- :GlossList — populate quickfix with all annotations in buffer
  handlers['GlossList'] = function(_opts)
    local bufnr = vim.api.nvim_get_current_buf()
    local annotations = annotation_mod.list(bufnr)

    if not annotations or #annotations == 0 then
      vim.notify('gloss: no annotations in buffer', vim.log.levels.INFO)
      return
    end

    local qf_items = {}
    for _, ann in ipairs(annotations) do
      -- First line of content as description, truncated
      local first_line = (ann.content or ''):match('^[^\n]*') or ''
      if #first_line > 80 then
        first_line = first_line:sub(1, 77) .. '...'
      end

      table.insert(qf_items, {
        bufnr = bufnr,
        lnum = ann.line_start + 1, -- 1-indexed for quickfix
        col = ann.col_start and (ann.col_start + 1) or 1,
        text = string.format('[%s] %s', ann.location_type, first_line),
        type = 'I', -- info
      })
    end

    vim.fn.setqflist({}, 'r', { title = 'Gloss annotations', items = qf_items })
    vim.cmd('copen')
    vim.notify(string.format('gloss: %d annotation(s) in quickfix', #qf_items), vim.log.levels.INFO)
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

--- Dispatch a command by name with the original opts.
--- Used by the lazy-load stub to avoid re-dispatch via vim.cmd,
--- which would lose visual context (visualmode(), marks).
--- @param cmd_name string
--- @param opts table
function M.dispatch(cmd_name, opts)
  local handler = handlers[cmd_name]
  if handler then
    handler(opts)
  end
end

return M

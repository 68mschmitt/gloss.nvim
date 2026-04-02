--- Floating window rendering for gloss.nvim
--- Creates, positions, and manages floating windows for annotation display.

local M = {}

--- @class gloss.FloatState
--- @field winid integer|nil Window id of the floating window
--- @field bufnr integer|nil Buffer number of the float content buffer
--- @field annotation_id string|nil ID of the annotation being displayed

--- Active float states keyed by source buffer number.
--- @type table<integer, gloss.FloatState[]>
local active_floats = {}

--- Compute the float position relative to an annotation location.
--- Accounts for window boundaries to avoid clipping.
--- @param source_bufnr integer The buffer the annotation references
--- @param line integer 0-indexed line of the annotation
--- @param content_height integer Actual content height after wrapping
--- @param cfg gloss.Config
--- @return table opts Options table for nvim_open_win
local function compute_position(source_bufnr, line, content_height, cfg)
  local win_height = vim.api.nvim_win_get_height(0)
  local height = math.min(content_height, cfg.float_max_height)

  -- Account for sign column / number column offset
  local wininfo = vim.fn.getwininfo(vim.api.nvim_get_current_win())
  local textoff = wininfo and wininfo[1] and wininfo[1].textoff or 0
  local col = textoff

  -- Convert buffer line to window-relative row via screenpos
  local screen = vim.fn.screenpos(vim.api.nvim_get_current_win(), line + 1, 1)
  local win_pos = vim.api.nvim_win_get_position(0)
  local row_in_win
  if screen and screen.row > 0 then
    row_in_win = screen.row - win_pos[1] -- window-relative row
  else
    -- Fallback: line is off-screen, use cursor's window-relative position
    row_in_win = vim.fn.winline()
  end

  -- Determine whether to place above or below the annotation line
  local anchor = 'NW'
  local row = row_in_win + 1 -- below the line (1-indexed row + 1 for spacing)

  -- Border adds 2 rows (top + bottom) to effective height
  local border_rows = 2
  local effective_height = height + border_rows

  -- If float would clip below the window, try placing above
  if row + effective_height > win_height then
    if row_in_win - 1 >= effective_height then
      -- Enough room above: flip to SW anchor
      anchor = 'SW'
      row = row_in_win - 1
    end
    -- If neither above nor below fits, keep below (will scroll/clip)
  end

  return {
    relative = 'win',
    anchor = anchor,
    row = row,
    col = col,
    width = width,
    height = height,
    border = cfg.float_border,
    style = 'minimal',
    focusable = true,
  }
end

--- Wrap content lines to fit within the float width.
--- Uses display width for correct multi-byte character handling.
--- Preserves lines inside fenced code blocks (``` ... ```) unwrapped.
--- @param lines string[]
--- @param width integer Display width to wrap at
--- @return string[]
local function wrap_lines(lines, width)
  local result = {}
  local in_code_block = false

  for _, line in ipairs(lines) do
    -- Toggle code block state on fence markers
    if line:match('^```') then
      in_code_block = not in_code_block
      table.insert(result, line)
    elseif in_code_block then
      -- Don't wrap inside code blocks
      table.insert(result, line)
    elseif vim.fn.strdisplaywidth(line) <= width then
      table.insert(result, line)
    else
      -- Word-wrap using display widths and character-safe slicing
      local chars = {}
      for _, c in vim.fn.str2list(line, true) do
        table.insert(chars, vim.fn.nr2char(c))
      end

      local current = {}
      local current_width = 0

      for _, ch in ipairs(chars) do
        local ch_width = vim.fn.strdisplaywidth(ch)

        if current_width + ch_width > width and #current > 0 then
          -- Try to break at a space
          local seg = table.concat(current)
          local last_space = seg:match('.*() ')
          if last_space and vim.fn.strdisplaywidth(seg:sub(1, last_space - 1)) > width * 0.4 then
            -- Break at last space
            table.insert(result, seg:sub(1, last_space - 1))
            -- Carry over the remainder after the space
            local remainder = seg:sub(last_space + 1)
            current = {}
            current_width = 0
            for _, rc in vim.fn.str2list(remainder, true) do
              local rch = vim.fn.nr2char(rc)
              table.insert(current, rch)
              current_width = current_width + vim.fn.strdisplaywidth(rch)
            end
          else
            -- Hard break at width
            table.insert(result, seg)
            current = {}
            current_width = 0
          end
        end

        table.insert(current, ch)
        current_width = current_width + ch_width
      end

      -- Flush remaining
      if #current > 0 then
        table.insert(result, table.concat(current))
      end
    end
  end

  return result
end

--- Open a floating window to display annotation content.
--- @param source_bufnr integer Buffer the annotation belongs to
--- @param annotation_id string Annotation id
--- @param content string Markdown content
--- @param line integer 0-indexed line of the annotation
--- @param cfg gloss.Config
--- @return integer|nil winid The window id, or nil on failure
function M.open(source_bufnr, annotation_id, content, line, cfg)
  -- Close any existing float for this annotation
  M.close_by_annotation(source_bufnr, annotation_id)

  -- Create a scratch buffer for the float content
  local float_buf = vim.api.nvim_create_buf(false, true)
  if not float_buf or float_buf == 0 then
    return nil
  end

  -- Split content into lines and set in buffer
  local lines = vim.split(content, '\n', { plain = true })
  local win_width = vim.api.nvim_win_get_width(0)
  local width = math.min(cfg.float_max_width, win_width - 4)
  local wrapped = wrap_lines(lines, width) -- border is excluded from content area by neovim

  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, wrapped)
  vim.bo[float_buf].modifiable = false
  vim.bo[float_buf].filetype = 'markdown'
  vim.bo[float_buf].bufhidden = 'wipe'

  -- Compute float dimensions based on actual content
  local float_height = math.max(math.min(#wrapped, cfg.float_max_height), 1)
  local opts = compute_position(source_bufnr, line, float_height, cfg)
  opts.width = width

  local winid = vim.api.nvim_open_win(float_buf, false, opts)
  if not winid or winid == 0 then
    vim.api.nvim_buf_delete(float_buf, { force = true })
    return nil
  end

  -- Enable scrolling in the float
  vim.wo[winid].scrolloff = 0
  vim.wo[winid].wrap = true
  vim.wo[winid].conceallevel = 2

  -- Track this float
  if not active_floats[source_bufnr] then
    active_floats[source_bufnr] = {}
  end
  table.insert(active_floats[source_bufnr], {
    winid = winid,
    bufnr = float_buf,
    annotation_id = annotation_id,
  })

  return winid
end

--- Close a float for a specific annotation.
--- @param source_bufnr integer
--- @param annotation_id string
function M.close_by_annotation(source_bufnr, annotation_id)
  local floats = active_floats[source_bufnr]
  if not floats then
    return
  end

  for i = #floats, 1, -1 do
    local f = floats[i]
    if f.annotation_id == annotation_id then
      if f.winid and vim.api.nvim_win_is_valid(f.winid) then
        vim.api.nvim_win_close(f.winid, true)
      end
      table.remove(floats, i)
    end
  end
end

--- Close all floats for a buffer.
--- @param source_bufnr integer
function M.close_all(source_bufnr)
  local floats = active_floats[source_bufnr]
  if not floats then
    return
  end

  for _, f in ipairs(floats) do
    if f.winid and vim.api.nvim_win_is_valid(f.winid) then
      vim.api.nvim_win_close(f.winid, true)
    end
  end

  active_floats[source_bufnr] = nil
end

--- Check if a float is open for a specific annotation.
--- @param source_bufnr integer
--- @param annotation_id string
--- @return boolean
function M.is_open(source_bufnr, annotation_id)
  local floats = active_floats[source_bufnr]
  if not floats then
    return false
  end

  for _, f in ipairs(floats) do
    if f.annotation_id == annotation_id and f.winid and vim.api.nvim_win_is_valid(f.winid) then
      return true
    end
  end
  return false
end

--- Get all active float states for a buffer.
--- @param source_bufnr integer
--- @return gloss.FloatState[]
function M.get_floats(source_bufnr)
  return active_floats[source_bufnr] or {}
end

--- Scroll a float window by delta lines.
--- @param source_bufnr integer
--- @param annotation_id string
--- @param delta integer Positive = down, negative = up
function M.scroll(source_bufnr, annotation_id, delta)
  local floats = active_floats[source_bufnr]
  if not floats then
    return
  end

  for _, f in ipairs(floats) do
    if f.annotation_id == annotation_id and f.winid and vim.api.nvim_win_is_valid(f.winid) then
      vim.api.nvim_win_call(f.winid, function()
        local cmd = delta > 0 and (delta .. [[\<C-e>]]) or (-delta .. [[\<C-y>]])
        vim.cmd('normal! ' .. vim.api.nvim_replace_termcodes(cmd, true, false, true))
      end)
      break
    end
  end
end

return M

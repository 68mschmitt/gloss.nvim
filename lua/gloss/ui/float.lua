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

--- Find the longest visible line in the annotation's line range.
--- Used to determine if there's room to place a float to the right.
--- @param source_bufnr integer
--- @param line_start integer 0-indexed
--- @param line_end integer 0-indexed
--- @return integer max display width of lines in the range
local function longest_line_in_range(source_bufnr, line_start, line_end)
  local lines = vim.api.nvim_buf_get_lines(source_bufnr, line_start, line_end + 1, false)
  local max_width = 0
  for _, l in ipairs(lines) do
    local w = vim.fn.strdisplaywidth(l)
    if w > max_width then
      max_width = w
    end
  end
  return max_width
end

--- Compute the float position relative to an annotation location.
--- Prefers right-side placement (inline with annotation) when there is room,
--- falling back to below/above the annotation line.
--- @param source_bufnr integer The buffer the annotation references
--- @param line integer 0-indexed line of the annotation
--- @param content_height integer Actual content height after wrapping
--- @param content_width integer Width of the float content area
--- @param cfg gloss.Config
--- @return table opts Options table for nvim_open_win
local function compute_position(source_bufnr, line, content_height, content_width, cfg)
  local win_width = vim.api.nvim_win_get_width(0)
  local win_height = vim.api.nvim_win_get_height(0)
  local height = math.min(content_height, cfg.float_max_height)

  -- Account for sign column / number column offset
  local wininfo = vim.fn.getwininfo(vim.api.nvim_get_current_win())
  local textoff = wininfo and wininfo[1] and wininfo[1].textoff or 0

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

  -- Border adds 2 cols/rows to effective dimensions
  local border_cols = 2
  local border_rows = 2

  -- Try right-side placement: float anchored to the right of source text,
  -- top-aligned with the annotation's start line.
  local source_width = longest_line_in_range(source_bufnr, line, line)
  local right_col = textoff + source_width + 2 -- 2 chars padding
  local available_right = win_width - right_col - border_cols
  local min_float_width = 30 -- don't show a float narrower than this

  if available_right >= min_float_width then
    -- Right-side placement fits. Clamp float width to available space.
    local right_width = math.min(content_width, available_right)
    return {
      relative = 'win',
      anchor = 'NW',
      row = row_in_win - 1, -- align top of float with the annotation line
      col = right_col,
      width = right_width,
      height = height,
      border = cfg.float_border,
      style = 'minimal',
      focusable = true,
    }
  end

  -- Fallback: below / above placement (original behaviour)
  local col = textoff
  local anchor = 'NW'
  local row = row_in_win + 1 -- below the line

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
    -- width is set by M.open() after calling compute_position
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
      for _, c in ipairs(vim.fn.str2list(line, true)) do
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
            for _, rc in ipairs(vim.fn.str2list(remainder, true)) do
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

--- Build a float title from the annotated source text.
--- Returns a short, truncated snippet of the referenced text for context.
--- @param source_bufnr integer
--- @param line_start integer 0-indexed
--- @param line_end integer 0-indexed
--- @param col_start integer|nil
--- @param col_end integer|nil
--- @return string title
local function build_title(source_bufnr, line_start, line_end, col_start, col_end)
  local lines = vim.api.nvim_buf_get_lines(source_bufnr, line_start, line_end + 1, false)
  if #lines == 0 then
    return string.format(' L%d ', line_start + 1)
  end

  local snippet
  if col_start and col_end and #lines == 1 then
    -- Word-level: extract the selected range
    snippet = lines[1]:sub(col_start + 1, col_end)
  else
    -- Line/range: use the first line, trimmed
    snippet = vim.trim(lines[1])
  end

  -- Truncate to keep the title readable
  local max_len = 40
  if #snippet > max_len then
    snippet = snippet:sub(1, max_len - 3) .. '...'
  end

  if line_start == line_end then
    return string.format(' L%d: %s ', line_start + 1, snippet)
  else
    return string.format(' L%d-%d: %s ', line_start + 1, line_end + 1, snippet)
  end
end

--- Open a floating window to display annotation content.
--- @param source_bufnr integer Buffer the annotation belongs to
--- @param annotation_id string Annotation id
--- @param content string Markdown content
--- @param line integer 0-indexed line of the annotation
--- @param cfg gloss.Config
--- @param ann_meta? {line_end: integer, col_start: integer|nil, col_end: integer|nil} Extra annotation fields for title
--- @return integer|nil winid The window id, or nil on failure
function M.open(source_bufnr, annotation_id, content, line, cfg, ann_meta)
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
  local opts = compute_position(source_bufnr, line, float_height, width, cfg)

  -- If compute_position already set width (right-side placement), re-wrap
  -- content to the narrower width for a clean fit.
  if opts.width and opts.width < width then
    width = opts.width
    wrapped = wrap_lines(vim.split(content, '\n', { plain = true }), width)
    vim.bo[float_buf].modifiable = true
    vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, wrapped)
    vim.bo[float_buf].modifiable = false
    float_height = math.max(math.min(#wrapped, cfg.float_max_height), 1)
    opts.height = float_height
  end

  -- Set width if not already determined by right-side placement
  if not opts.width then
    opts.width = width
  end

  -- Add title with source context
  local line_end = ann_meta and ann_meta.line_end or line
  local col_start = ann_meta and ann_meta.col_start or nil
  local col_end = ann_meta and ann_meta.col_end or nil
  opts.title = build_title(source_bufnr, line, line_end, col_start, col_end)
  opts.title_pos = 'left'

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

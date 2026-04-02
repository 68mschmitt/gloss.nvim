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
--- @param source_bufnr integer The buffer the annotation references
--- @param line integer 0-indexed line of the annotation
--- @param cfg gloss.Config
--- @return table opts Options table for nvim_open_win
local function compute_position(source_bufnr, line, cfg)
  local win_width = vim.api.nvim_win_get_width(0)
  local width = math.min(cfg.float_max_width, win_width - 4)
  local height = math.min(cfg.float_max_height, 10) -- initial; resized after content

  return {
    relative = 'win',
    anchor = 'NW',
    row = line + 1, -- below the annotation line
    col = 2,
    width = width,
    height = height,
    border = cfg.float_border,
    style = 'minimal',
    focusable = true,
  }
end

--- Wrap content lines to fit within the float width.
--- @param lines string[]
--- @param width integer
--- @return string[]
local function wrap_lines(lines, width)
  local result = {}
  for _, line in ipairs(lines) do
    if #line <= width then
      table.insert(result, line)
    else
      -- Simple word-wrap
      local pos = 1
      while pos <= #line do
        local segment = line:sub(pos, pos + width - 1)
        -- Try to break at a space if we're not at the end
        if pos + width - 1 < #line then
          local last_space = segment:match('.*() ')
          if last_space and last_space > width * 0.4 then
            segment = line:sub(pos, pos + last_space - 2)
            pos = pos + last_space
          else
            pos = pos + width
          end
        else
          pos = pos + width
        end
        table.insert(result, segment)
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
  local wrapped = wrap_lines(lines, width - 2) -- account for padding

  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, wrapped)
  vim.bo[float_buf].modifiable = false
  vim.bo[float_buf].filetype = 'markdown'
  vim.bo[float_buf].bufhidden = 'wipe'

  -- Compute float dimensions based on actual content
  local float_height = math.min(#wrapped, cfg.float_max_height)
  local opts = compute_position(source_bufnr, line, cfg)
  opts.height = math.max(float_height, 1)
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
        local cmd = delta > 0 and (delta .. [[\<C-e>]]) or ((-delta) .. [[\<C-y>]])
        vim.cmd('normal! ' .. vim.api.nvim_replace_termcodes(cmd, true, false, true))
      end)
      break
    end
  end
end

return M

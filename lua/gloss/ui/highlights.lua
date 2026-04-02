--- Highlight group definitions for gloss.nvim
--- Sets up default highlight groups for signs and referenced text.

local M = {}

--- Define default highlight groups (user can override via :highlight).
function M.setup()
  -- Sign column icon highlight
  vim.api.nvim_set_hl(0, 'GlossSign', { default = true, fg = '#7aa2f7', bold = true })
  -- Subtle underline for referenced text in collapsed state
  vim.api.nvim_set_hl(0, 'GlossHighlight', { default = true, underline = true, sp = '#565f89' })
  -- Highlight for referenced text when annotation is expanded
  vim.api.nvim_set_hl(
    0,
    'GlossHighlightActive',
    { default = true, underline = true, sp = '#7aa2f7' }
  )
end

--- Apply highlight to a location in a buffer.
--- @param bufnr integer Buffer number
--- @param ns_id integer Namespace id
--- @param line_start integer 0-indexed first line
--- @param line_end integer 0-indexed last line
--- @param col_start integer|nil Column start (for word-level)
--- @param col_end integer|nil Column end (for word-level)
--- @param active boolean Whether annotation is expanded
--- @return integer extmark_id The extmark id for the highlight
function M.apply(bufnr, ns_id, line_start, line_end, col_start, col_end, active)
  local hl = active and 'GlossHighlightActive' or 'GlossHighlight'

  if col_start and col_end then
    -- Word-level: highlight specific columns on a single line
    return vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_start, col_start, {
      end_col = col_end,
      hl_group = hl,
    })
  else
    -- Line or range: highlight full lines
    return vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_start, 0, {
      end_row = line_end + 1,
      hl_group = hl,
      hl_eol = true,
    })
  end
end

--- Remove a specific highlight extmark.
--- @param bufnr integer
--- @param ns_id integer
--- @param extmark_id integer
function M.clear(bufnr, ns_id, extmark_id)
  vim.api.nvim_buf_del_extmark(bufnr, ns_id, extmark_id)
end

--- Remove all highlight extmarks in a buffer for our namespace.
--- @param bufnr integer
--- @param ns_id integer
function M.clear_all(bufnr, ns_id)
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

return M

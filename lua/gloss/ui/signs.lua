--- Sign (gutter icon) management for gloss.nvim
--- Places and removes sign column icons for annotations.

local M = {}

--- Place a sign icon on a line for an annotation.
--- @param bufnr integer Buffer number
--- @param ns_id integer Namespace id
--- @param line integer 0-indexed line number
--- @param sign_text string Sign text (1-2 chars)
--- @param sign_hl string Highlight group for the sign
--- @return integer extmark_id
function M.place(bufnr, ns_id, line, sign_text, sign_hl)
  return vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
    sign_text = sign_text,
    sign_hl_group = sign_hl,
    priority = 10,
  })
end

--- Remove a specific sign extmark.
--- @param bufnr integer
--- @param ns_id integer
--- @param extmark_id integer
function M.remove(bufnr, ns_id, extmark_id)
  vim.api.nvim_buf_del_extmark(bufnr, ns_id, extmark_id)
end

--- Remove all signs in a buffer for our namespace.
--- @param bufnr integer
--- @param ns_id integer
function M.clear_all(bufnr, ns_id)
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

return M

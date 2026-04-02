--- Position tracking for gloss.nvim
--- Uses content hashes and extmarks to track annotation positions across edits.

local M = {}

local ns_id = require('gloss.config').ns.tracker

--- Place extmarks for all annotations in a buffer.
--- Called after loading/reconciling to track positions during editing.
--- @param bufnr integer
--- @param annotation_mod table The gloss.core.annotation module
function M.place_extmarks(bufnr, annotation_mod)
  local annotations = annotation_mod.list(bufnr)
  if not annotations then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)

  for _, ann in ipairs(annotations) do
    -- Clamp line to valid range
    local line = math.min(ann.line_start, line_count - 1)
    line = math.max(line, 0)

    local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
      right_gravity = false, -- move with text above
    })
    ann.extmark_id = extmark_id
  end
end

--- Reconcile annotation positions after loading from disk.
--- Uses content hash to verify/correct positions.
---
--- Strategy:
--- 1. Check stored line for matching content hash (fast path)
--- 2. Search nearby lines for matching hash (slow path, expanding window)
--- 3. Fall back to line 0 if content is gone entirely
---
--- @param bufnr integer
--- @param annotation_mod table The gloss.core.annotation module
function M.reconcile(bufnr, annotation_mod)
  local annotations = annotation_mod.list(bufnr)
  if not annotations then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)

  for _, ann in ipairs(annotations) do
    -- Ensure line is in bounds
    local stored_line = math.min(ann.line_start, line_count - 1)
    stored_line = math.max(stored_line, 0)

    local line_delta = ann.line_end - ann.line_start
    local stored_end = math.min(stored_line + line_delta, line_count - 1)

    -- Fast path: check stored line
    local current_hash =
      annotation_mod.compute_hash(bufnr, stored_line, stored_end, ann.col_start, ann.col_end)
    if current_hash == ann.content_hash then
      -- Position is correct, just clamp
      ann.line_start = stored_line
      ann.line_end = stored_end
    else
      -- Slow path: search nearby lines with expanding window
      local found = false
      local max_search = math.min(50, line_count) -- don't search forever

      for offset = 1, max_search do
        -- Check above
        local check_line = stored_line - offset
        if check_line >= 0 then
          local check_end = math.min(check_line + line_delta, line_count - 1)
          local h =
            annotation_mod.compute_hash(bufnr, check_line, check_end, ann.col_start, ann.col_end)
          if h == ann.content_hash then
            ann.line_start = check_line
            ann.line_end = check_end
            found = true
            break
          end
        end

        -- Check below
        check_line = stored_line + offset
        if check_line < line_count then
          local check_end = math.min(check_line + line_delta, line_count - 1)
          local h =
            annotation_mod.compute_hash(bufnr, check_line, check_end, ann.col_start, ann.col_end)
          if h == ann.content_hash then
            ann.line_start = check_line
            ann.line_end = check_end
            found = true
            break
          end
        end
      end

      if not found then
        -- Fall back to line 0
        ann.line_start = 0
        ann.line_end = 0 + line_delta
        if ann.line_end >= line_count then
          ann.line_end = line_count - 1
        end
      end
    end
  end

  -- Place extmarks at reconciled positions
  M.place_extmarks(bufnr, annotation_mod)
end

--- Sync annotation positions from extmark positions.
--- Called on BufWritePost to capture where extmarks have moved.
--- @param bufnr integer
--- @param annotation_mod table The gloss.core.annotation module
function M.sync_from_extmarks(bufnr, annotation_mod)
  local annotations = annotation_mod.list(bufnr)
  if not annotations then
    return
  end

  for _, ann in ipairs(annotations) do
    if ann.extmark_id then
      local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, ann.extmark_id, {})
      if pos and #pos >= 1 then
        local new_line = pos[1]
        local line_delta = ann.line_end - ann.line_start
        ann.line_start = new_line
        ann.line_end = new_line + line_delta

        -- Update content hash at new position
        ann.content_hash = annotation_mod.compute_hash(
          bufnr,
          ann.line_start,
          ann.line_end,
          ann.col_start,
          ann.col_end
        )
      end
    end
  end
end

--- Clear all tracker extmarks for a buffer.
--- @param bufnr integer
function M.clear(bufnr)
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns_id, 0, -1)
end

return M

--- Overlap detection and annotation cycling for gloss.nvim
--- Handles GlossNext/GlossPrev when multiple annotations exist at the same position.

local M = {}

--- Track the currently focused annotation index at each line, per buffer.
--- @type table<integer, table<integer, integer>> bufnr -> line -> focus_index
local focus_state = {}

--- Get all annotations at a given line, sorted by creation time.
--- @param bufnr integer
--- @param line integer 0-indexed
--- @param annotation_mod table
--- @return gloss.Annotation[]
local function get_annotations_at(bufnr, line, annotation_mod)
  local all = annotation_mod.find_all_at(bufnr, line)

  -- Sort by created_at for stable ordering
  table.sort(all, function(a, b)
    return a.created_at < b.created_at
  end)

  return all
end

--- Get the current focus index for a line in a buffer.
--- @param bufnr integer
--- @param line integer
--- @return integer 1-indexed focus position
local function get_focus(bufnr, line)
  if not focus_state[bufnr] then
    focus_state[bufnr] = {}
  end
  return focus_state[bufnr][line] or 1
end

--- Set the focus index for a line in a buffer.
--- @param bufnr integer
--- @param line integer
--- @param idx integer
local function set_focus(bufnr, line, idx)
  if not focus_state[bufnr] then
    focus_state[bufnr] = {}
  end
  focus_state[bufnr][line] = idx
end

--- Show the focused annotation at a position.
--- Collapses all others at that position and expands the focused one.
--- @param bufnr integer
--- @param annotations gloss.Annotation[]
--- @param focus_idx integer 1-indexed
--- @param annotation_mod table
--- @param cfg gloss.Config
--- @param ns_id integer
local function show_focused(bufnr, annotations, focus_idx, annotation_mod, cfg, ns_id)
  local float = require('gloss.ui.float')
  local signs = require('gloss.ui.signs')
  local highlights = require('gloss.ui.highlights')

  for i, ann in ipairs(annotations) do
    if i == focus_idx then
      -- Expand the focused one
      annotation_mod.set_collapsed(bufnr, ann.id, false)
      float.open(bufnr, ann.id, ann.content, ann.line_start, cfg)
      highlights.apply(bufnr, ns_id, ann.line_start, ann.line_end, ann.col_start, ann.col_end, true)
    else
      -- Collapse all others
      annotation_mod.set_collapsed(bufnr, ann.id, true)
      float.close_by_annotation(bufnr, ann.id)
      highlights.apply(bufnr, ns_id, ann.line_start, ann.line_end, ann.col_start, ann.col_end, false)
    end

    -- Sign is always present
    signs.place(bufnr, ns_id, ann.line_start, cfg.sign_text, cfg.sign_hl)
  end

  -- Notify which annotation is focused
  if #annotations > 1 then
    vim.notify(
      string.format('gloss: annotation %d/%d', focus_idx, #annotations),
      vim.log.levels.INFO
    )
  end
end

--- Cycle to the next annotation at the cursor position.
--- @param bufnr integer
--- @param line integer 0-indexed cursor line
--- @param annotation_mod table
--- @param cfg gloss.Config
--- @param ns_id integer
function M.next(bufnr, line, annotation_mod, cfg, ns_id)
  local annotations = get_annotations_at(bufnr, line, annotation_mod)
  if #annotations == 0 then
    vim.notify('gloss: no annotations at cursor', vim.log.levels.WARN)
    return
  end

  if #annotations == 1 then
    -- Single annotation: just toggle expand
    local ann = annotations[1]
    local new_state = not ann.collapsed
    annotation_mod.set_collapsed(bufnr, ann.id, new_state)
    show_focused(bufnr, annotations, 1, annotation_mod, cfg, ns_id)
    return
  end

  -- Multiple annotations: cycle forward
  local current = get_focus(bufnr, line)
  local next_idx = (current % #annotations) + 1
  set_focus(bufnr, line, next_idx)
  show_focused(bufnr, annotations, next_idx, annotation_mod, cfg, ns_id)
end

--- Cycle to the previous annotation at the cursor position.
--- @param bufnr integer
--- @param line integer 0-indexed cursor line
--- @param annotation_mod table
--- @param cfg gloss.Config
--- @param ns_id integer
function M.prev(bufnr, line, annotation_mod, cfg, ns_id)
  local annotations = get_annotations_at(bufnr, line, annotation_mod)
  if #annotations == 0 then
    vim.notify('gloss: no annotations at cursor', vim.log.levels.WARN)
    return
  end

  if #annotations == 1 then
    local ann = annotations[1]
    local new_state = not ann.collapsed
    annotation_mod.set_collapsed(bufnr, ann.id, new_state)
    show_focused(bufnr, annotations, 1, annotation_mod, cfg, ns_id)
    return
  end

  local current = get_focus(bufnr, line)
  local prev_idx = ((current - 2) % #annotations) + 1
  set_focus(bufnr, line, prev_idx)
  show_focused(bufnr, annotations, prev_idx, annotation_mod, cfg, ns_id)
end

--- Clear focus state for a buffer.
--- @param bufnr integer
function M.clear(bufnr)
  focus_state[bufnr] = nil
end

return M

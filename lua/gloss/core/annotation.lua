--- Annotation data model and CRUD operations for gloss.nvim
--- Manages in-memory annotation state per buffer.

local M = {}

--- @class gloss.Annotation
--- @field id string Unique identifier (timestamp-hex)
--- @field content string Markdown content
--- @field location_type string "line" | "word" | "range"
--- @field line_start integer 0-indexed first line
--- @field line_end integer 0-indexed last line
--- @field col_start integer|nil Column start (word-level only)
--- @field col_end integer|nil Column end (word-level only)
--- @field content_hash string Hash of referenced buffer text at creation
--- @field collapsed boolean Current display state
--- @field created_at string ISO 8601 timestamp
--- @field extmark_id integer|nil Extmark id for position tracking (runtime only, not persisted)

--- In-memory annotation storage: bufnr -> annotation[]
--- @type table<integer, gloss.Annotation[]>
local buffer_annotations = {}

--- Generate a unique annotation ID.
--- Uses vim.uv.hrtime() for nanosecond-resolution uniqueness,
--- avoiding pollution of the global Lua PRNG.
--- Format: timestamp-hrtime_hex (e.g. "1743465600-00000003a3f2b1c0")
--- @return string
local function generate_id()
  local hrtime = vim.uv.hrtime()
  return string.format('%d-%016x', os.time(), hrtime)
end

--- Compute a content hash for the referenced text in a buffer.
--- Uses a simple djb2-style hash, returned as hex string.
--- @param bufnr integer
--- @param line_start integer 0-indexed
--- @param line_end integer 0-indexed
--- @param col_start integer|nil
--- @param col_end integer|nil
--- @return string hash
function M.compute_hash(bufnr, line_start, line_end, col_start, col_end)
  local lines = vim.api.nvim_buf_get_lines(bufnr, line_start, line_end + 1, false)
  if #lines == 0 then
    return 'empty'
  end

  -- For word-level, extract the specific column range
  if col_start and col_end and #lines == 1 then
    lines[1] = lines[1]:sub(col_start + 1, col_end)
  end

  local text = table.concat(lines, '\n')

  -- djb2 hash
  local hash = 5381
  for i = 1, #text do
    hash = ((hash * 33) + text:byte(i)) % 0xFFFFFFFF
  end

  return string.format('djb2:%08x', hash)
end

--- Create a new annotation in a buffer.
--- @param bufnr integer Buffer number
--- @param params table { content, location_type, line_start, line_end, col_start?, col_end? }
--- @return gloss.Annotation
function M.create(bufnr, params)
  if not buffer_annotations[bufnr] then
    buffer_annotations[bufnr] = {}
  end

  local annotation = {
    id = generate_id(),
    content = params.content,
    location_type = params.location_type or 'line',
    line_start = params.line_start,
    line_end = params.line_end,
    col_start = params.col_start,
    col_end = params.col_end,
    content_hash = M.compute_hash(
      bufnr,
      params.line_start,
      params.line_end,
      params.col_start,
      params.col_end
    ),
    collapsed = true, -- start collapsed
    created_at = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    extmark_id = nil,
  }

  table.insert(buffer_annotations[bufnr], annotation)
  return annotation
end

--- List all annotations for a buffer.
--- @param bufnr integer
--- @return gloss.Annotation[]|nil
function M.list(bufnr)
  return buffer_annotations[bufnr]
end

--- Find annotation(s) at a specific line.
--- @param bufnr integer
--- @param line integer 0-indexed line number
--- @return gloss.Annotation|nil First matching annotation
function M.find_at(bufnr, line)
  local annotations = buffer_annotations[bufnr]
  if not annotations then
    return nil
  end

  for _, ann in ipairs(annotations) do
    if line >= ann.line_start and line <= ann.line_end then
      return ann
    end
  end

  return nil
end

--- Find all annotations at a specific line.
--- @param bufnr integer
--- @param line integer 0-indexed line number
--- @return gloss.Annotation[]
function M.find_all_at(bufnr, line)
  local result = {}
  local annotations = buffer_annotations[bufnr]
  if not annotations then
    return result
  end

  for _, ann in ipairs(annotations) do
    if line >= ann.line_start and line <= ann.line_end then
      table.insert(result, ann)
    end
  end

  return result
end

--- Find an annotation by ID.
--- @param bufnr integer
--- @param id string
--- @return gloss.Annotation|nil
function M.find_by_id(bufnr, id)
  local annotations = buffer_annotations[bufnr]
  if not annotations then
    return nil
  end

  for _, ann in ipairs(annotations) do
    if ann.id == id then
      return ann
    end
  end

  return nil
end

--- Delete an annotation by ID.
--- @param bufnr integer
--- @param id string
--- @return boolean True if annotation was found and deleted
function M.delete(bufnr, id)
  local annotations = buffer_annotations[bufnr]
  if not annotations then
    return false
  end

  for i, ann in ipairs(annotations) do
    if ann.id == id then
      table.remove(annotations, i)
      return true
    end
  end

  return false
end

--- Set the collapsed state of an annotation.
--- @param bufnr integer
--- @param id string
--- @param collapsed boolean
function M.set_collapsed(bufnr, id, collapsed)
  local ann = M.find_by_id(bufnr, id)
  if ann then
    ann.collapsed = collapsed
  end
end

--- Update an annotation's content (used by GlossEdit).
--- Preserves id, created_at, and position.
--- @param bufnr integer
--- @param id string
--- @param content string New markdown content
function M.update_content(bufnr, id, content)
  local ann = M.find_by_id(bufnr, id)
  if ann then
    ann.content = content
  end
end

--- Update an annotation's position (used by tracker).
--- @param bufnr integer
--- @param id string
--- @param line_start integer
--- @param line_end integer
function M.update_position(bufnr, id, line_start, line_end)
  local ann = M.find_by_id(bufnr, id)
  if ann then
    ann.line_start = line_start
    ann.line_end = line_end
  end
end

--- Load annotations from parsed data (used by store on buffer load).
--- @param bufnr integer
--- @param annotations gloss.Annotation[]
function M.load(bufnr, annotations)
  buffer_annotations[bufnr] = annotations
end

--- Get annotations in a serializable format (strips runtime-only fields).
--- @param bufnr integer
--- @return table[]|nil
function M.serialize(bufnr)
  local annotations = buffer_annotations[bufnr]
  if not annotations then
    return nil
  end

  local result = {}
  for _, ann in ipairs(annotations) do
    table.insert(result, {
      id = ann.id,
      content = ann.content,
      location_type = ann.location_type,
      line_start = ann.line_start,
      line_end = ann.line_end,
      col_start = ann.col_start,
      col_end = ann.col_end,
      content_hash = ann.content_hash,
      collapsed = ann.collapsed,
      created_at = ann.created_at,
    })
  end

  return result
end

--- Clear all annotations for a buffer (used on buffer unload).
--- @param bufnr integer
function M.clear(bufnr)
  buffer_annotations[bufnr] = nil
end

return M

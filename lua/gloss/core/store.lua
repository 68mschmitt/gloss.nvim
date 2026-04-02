--- JSON persistence for gloss.nvim
--- Reads/writes gloss files and manages the index file.

local M = {}

--- @type table<integer, string> bufnr -> filepath that the buffer represents
local buffer_filepaths = {}

--- @type table<integer, string> bufnr -> gloss file path
local buffer_gloss_paths = {}

--- Compute the default gloss file path for a given source file.
--- Uses a hash of the absolute path as the filename.
--- @param filepath string Absolute path of the source file
--- @param state_dir string State directory
--- @return string gloss_file_path
local function default_gloss_path(filepath, state_dir)
  -- djb2 hash of filepath
  local hash = 5381
  for i = 1, #filepath do
    hash = ((hash * 33) + filepath:byte(i)) % 0xFFFFFFFF
  end
  local hashed = string.format('%08x', hash)
  return vim.fs.joinpath(state_dir, hashed .. '.json')
end

--- Read and parse a JSON file.
--- @param path string
--- @return table|nil data Parsed data, or nil on error
local function read_json(path)
  local f = io.open(path, 'r')
  if not f then
    return nil
  end

  local content = f:read('*a')
  f:close()

  if not content or content == '' then
    return nil
  end

  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    vim.notify('gloss: failed to parse JSON: ' .. path, vim.log.levels.ERROR)
    return nil
  end

  return data
end

--- Write data as JSON to a file.
--- @param path string
--- @param data table
--- @return boolean success
local function write_json(path, data)
  local ok, encoded = pcall(vim.json.encode, data)
  if not ok then
    vim.notify('gloss: failed to encode JSON', vim.log.levels.ERROR)
    return false
  end

  -- Ensure parent directory exists
  local dir = vim.fs.dirname(path)
  vim.fn.mkdir(dir, 'p')

  local f = io.open(path, 'w')
  if not f then
    vim.notify('gloss: cannot write file: ' .. path, vim.log.levels.ERROR)
    return false
  end

  f:write(encoded)
  f:close()
  return true
end

--- Read the index file to find custom gloss file mappings.
--- @param state_dir string
--- @return table<string, string> Mapping of filepath -> gloss path
local function read_index(state_dir)
  local index_path = vim.fs.joinpath(state_dir, 'index.json')
  local data = read_json(index_path)
  if data and data.mappings then
    return data.mappings
  end
  return {}
end

--- Write the index file.
--- @param state_dir string
--- @param mappings table<string, string>
local function write_index(state_dir, mappings)
  local index_path = vim.fs.joinpath(state_dir, 'index.json')
  write_json(index_path, {
    version = 1,
    mappings = mappings,
  })
end

--- Resolve the gloss file path for a source file.
--- Checks the index for custom mappings, falls back to default hashed path.
--- @param filepath string
--- @return string gloss_path
function M.resolve_gloss_path(filepath)
  local cfg = require('gloss.config').get()
  local mappings = read_index(cfg.state_dir)

  if mappings[filepath] then
    return mappings[filepath]
  end

  return default_gloss_path(filepath, cfg.state_dir)
end

--- Check if a gloss file exists for a given source file.
--- @param filepath string Absolute path of source file
--- @return boolean
function M.has_gloss_file(filepath)
  local gloss_path = M.resolve_gloss_path(filepath)
  return vim.fn.filereadable(gloss_path) == 1
end

--- Load annotations from a gloss file into a buffer.
--- @param bufnr integer
--- @param filepath string Absolute path of the source file
--- @param custom_gloss_path string|nil Optional custom gloss file path
function M.load(bufnr, filepath, custom_gloss_path)
  local cfg = require('gloss.config').get()
  local annotation = require('gloss.core.annotation')

  buffer_filepaths[bufnr] = filepath

  local gloss_path
  if custom_gloss_path then
    -- Register custom mapping in index
    local mappings = read_index(cfg.state_dir)
    mappings[filepath] = custom_gloss_path
    write_index(cfg.state_dir, mappings)
    gloss_path = custom_gloss_path
  else
    gloss_path = M.resolve_gloss_path(filepath)
  end

  buffer_gloss_paths[bufnr] = gloss_path

  local data = read_json(gloss_path)
  if not data or not data.annotations then
    annotation.load(bufnr, {})
    return
  end

  -- Convert stored annotation data into runtime objects
  local annotations = {}
  for _, stored in ipairs(data.annotations) do
    table.insert(annotations, {
      id = stored.id,
      content = stored.content,
      location_type = stored.location_type or 'line',
      line_start = stored.line_start,
      line_end = stored.line_end,
      col_start = stored.col_start,
      col_end = stored.col_end,
      content_hash = stored.content_hash,
      collapsed = stored.collapsed ~= false, -- default to collapsed
      created_at = stored.created_at,
      extmark_id = nil,
    })
  end

  annotation.load(bufnr, annotations)
end

--- Save annotations for a buffer to its gloss file.
--- @param bufnr integer
function M.save(bufnr)
  local annotation = require('gloss.core.annotation')
  local filepath = buffer_filepaths[bufnr]

  if not filepath then
    -- Buffer was never loaded — resolve path now
    filepath = vim.api.nvim_buf_get_name(bufnr)
    if filepath == '' then
      return
    end
    buffer_filepaths[bufnr] = filepath
  end

  local gloss_path = buffer_gloss_paths[bufnr]
  if not gloss_path then
    gloss_path = M.resolve_gloss_path(filepath)
    buffer_gloss_paths[bufnr] = gloss_path
  end

  local serialized = annotation.serialize(bufnr)
  if not serialized then
    return
  end

  -- Don't write empty gloss files
  if #serialized == 0 then
    -- If the file exists, remove it
    if vim.fn.filereadable(gloss_path) == 1 then
      os.remove(gloss_path)
    end
    return
  end

  write_json(gloss_path, {
    version = 1,
    file = filepath,
    annotations = serialized,
  })
end

--- Get the filepath associated with a buffer.
--- @param bufnr integer
--- @return string|nil
function M.get_filepath(bufnr)
  return buffer_filepaths[bufnr]
end

--- Get the gloss file path associated with a buffer.
--- @param bufnr integer
--- @return string|nil
function M.get_gloss_path(bufnr)
  return buffer_gloss_paths[bufnr]
end

--- Clear all in-memory state for a buffer (used on buffer unload).
--- @param bufnr integer
function M.clear(bufnr)
  buffer_filepaths[bufnr] = nil
  buffer_gloss_paths[bufnr] = nil
end

return M

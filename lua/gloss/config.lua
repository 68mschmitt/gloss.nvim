--- Configuration for gloss.nvim
--- Defines defaults and merges user-provided options.

local M = {}

--- @class gloss.Config
--- @field state_dir string Directory for gloss files and index
--- @field sign_text string Gutter icon text (1-2 chars)
--- @field sign_hl string Highlight group for the sign
--- @field hl_group string Highlight group for referenced text
--- @field float_border string|string[] Border style for floating windows
--- @field float_max_width integer Maximum width for annotation floats
--- @field float_max_height integer Maximum height for annotation floats
--- @field edit_height integer Height of the scratch buffer split for editing

--- @type gloss.Config
local defaults = {
  state_dir = vim.fs.joinpath(vim.fn.stdpath('state'), 'gloss'),
  sign_text = '',
  sign_hl = 'GlossSign',
  hl_group = 'GlossHighlight',
  float_border = 'rounded',
  float_max_width = 60,
  float_max_height = 20,
  edit_height = 10,
}

--- @type gloss.Config|nil
local current = nil

--- Merge user options with defaults and store the result.
--- @param opts table|nil User-provided options
--- @return gloss.Config
function M.setup(opts)
  current = vim.tbl_deep_extend('force', {}, defaults, opts or {})
  return current
end

--- Return the active config. Errors if setup() has not been called.
--- @return gloss.Config
function M.get()
  if not current then
    error('gloss.nvim: setup() has not been called')
  end
  return current
end

--- Return a copy of the default config (useful for tests / health).
--- @return gloss.Config
function M.defaults()
  return vim.tbl_deep_extend('force', {}, defaults)
end

return M

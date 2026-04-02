--- Configuration for gloss.nvim
--- Defines defaults, constants, and merges user-provided options.

local M = {}

--- Namespace IDs used across the plugin.
--- Defined here so all modules reference the same names.
--- @type table<string, integer>
M.ns = {
  --- Namespace for signs and highlights (UI rendering)
  gloss = vim.api.nvim_create_namespace('gloss'),
  --- Namespace for position-tracking extmarks
  tracker = vim.api.nvim_create_namespace('gloss_tracker'),
}

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

--- Validate user-provided options.
--- @param opts table
local function validate(opts)
  vim.validate('state_dir', opts.state_dir, 'string', true)
  vim.validate('sign_text', opts.sign_text, 'string', true)
  vim.validate('sign_hl', opts.sign_hl, 'string', true)
  vim.validate('hl_group', opts.hl_group, 'string', true)
  vim.validate('float_border', opts.float_border, { 'string', 'table' }, true)
  vim.validate('float_max_width', opts.float_max_width, 'number', true)
  vim.validate('float_max_height', opts.float_max_height, 'number', true)
  vim.validate('edit_height', opts.edit_height, 'number', true)
end

--- Merge user options with defaults and store the result.
--- @param opts table|nil User-provided options
--- @return gloss.Config
function M.setup(opts)
  if opts then
    validate(opts)
  end
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

--- Minimal neovim config for running tests.
--- Adds the plugin and mini.test to the runtime path.

-- Add the plugin itself to rtp
vim.opt.rtp:prepend('.')

-- Add mini.test dependency
local mini_test_path = vim.fn.fnamemodify('deps/mini.test', ':p')
if vim.fn.isdirectory(mini_test_path) == 1 then
  vim.opt.rtp:append(mini_test_path)
end

-- Disable swap files and shada for test isolation
vim.opt.swapfile = false
vim.opt.shadafile = 'NONE'

-- Minimal settings
vim.opt.termguicolors = true
vim.cmd('filetype plugin indent on')
vim.cmd('syntax enable')

--- Health check for gloss.nvim
--- Verifies the environment meets plugin assumptions.

local M = {}

function M.check()
  local health = vim.health

  health.start('gloss.nvim')

  -- 1. Neovim version
  if vim.fn.has('nvim-0.12') == 1 then
    health.ok('neovim >= 0.12')
  else
    local v = vim.version()
    health.error('neovim >= 0.12 required', {
      'Current: ' .. v.major .. '.' .. v.minor .. '.' .. v.patch,
    })
  end

  -- 2. vim.json availability
  if vim.json and vim.json.encode and vim.json.decode then
    health.ok('vim.json available')
  else
    health.error('vim.json not available (requires neovim 0.6+)')
  end

  -- 3. State directory
  local ok_config, cfg = pcall(function()
    return require('gloss.config').get()
  end)

  if not ok_config then
    -- setup() hasn't been called yet, use defaults
    cfg = require('gloss.config').defaults()
    health.info('setup() not yet called, checking default state_dir')
  end

  local state_dir = cfg.state_dir
  if vim.fn.isdirectory(state_dir) == 1 then
    -- Test write access
    local test_file = vim.fs.joinpath(state_dir, '.gloss_health_check')
    local write_ok = pcall(function()
      local f = io.open(test_file, 'w')
      if not f then
        error('cannot open')
      end
      f:write('ok')
      f:close()
      os.remove(test_file)
    end)

    if write_ok then
      health.ok('state directory writable: ' .. state_dir)
    else
      health.error('state directory not writable: ' .. state_dir)
    end
  else
    health.warn('state directory does not exist yet: ' .. state_dir, {
      'It will be created on first annotation.',
    })
  end

  -- 4. Index file integrity (if it exists)
  local index_path = vim.fs.joinpath(state_dir, 'index.json')
  if vim.fn.filereadable(index_path) == 1 then
    local read_ok, data = pcall(function()
      local f = io.open(index_path, 'r')
      if not f then
        error('cannot open')
      end
      local content = f:read('*a')
      f:close()
      return vim.json.decode(content)
    end)

    if read_ok and type(data) == 'table' then
      health.ok('index file valid JSON')
      if data.version then
        health.ok('index file version: ' .. tostring(data.version))
      end
    else
      health.error('index file is corrupt or unreadable', {
        'Path: ' .. index_path,
        'Try deleting it and re-attaching gloss files.',
      })
    end
  else
    health.info('no index file yet (normal for first use)')
  end

  -- 5. Sign column support
  if vim.fn.has('signs') == 1 then
    health.ok('sign column supported')
  else
    health.error('sign column not available')
  end
end

return M

--- Tests for gloss.core.store

local new_set = MiniTest.new_set
local expect = MiniTest.expect

local T = new_set()

local store = require('gloss.core.store')
local annotation = require('gloss.core.annotation')
local config = require('gloss.config')

-- Use a temp directory for test state
local test_state_dir

T['setup'] = new_set({
  hooks = {
    pre_case = function()
      test_state_dir = vim.fn.tempname() .. '_gloss_test'
      vim.fn.mkdir(test_state_dir, 'p')
      config.setup({ state_dir = test_state_dir })
    end,
    post_case = function()
      -- Clean up temp dir
      vim.fn.delete(test_state_dir, 'rf')
    end,
  },
})

T['setup']['resolve_gloss_path() returns path in state dir'] = function()
  local path = store.resolve_gloss_path('/home/user/test.md')
  -- Should be inside state_dir and end with .json
  expect.equality(path:find(test_state_dir, 1, true) ~= nil, true)
  expect.equality(path:match('%.json$') ~= nil, true)
end

T['setup']['resolve_gloss_path() is deterministic'] = function()
  local path1 = store.resolve_gloss_path('/home/user/test.md')
  local path2 = store.resolve_gloss_path('/home/user/test.md')
  expect.equality(path1, path2)
end

T['setup']['resolve_gloss_path() different files get different paths'] = function()
  local path1 = store.resolve_gloss_path('/home/user/test.md')
  local path2 = store.resolve_gloss_path('/home/user/other.md')
  expect.no_equality(path1, path2)
end

T['setup']['has_gloss_file() returns false when no file exists'] = function()
  expect.equality(store.has_gloss_file('/nonexistent/file.md'), false)
end

T['setup']['save() and load() round-trip annotations'] = function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'line one', 'line two' })
  vim.api.nvim_buf_set_name(buf, '/tmp/gloss_test_roundtrip.md')

  -- Create an annotation
  annotation.create(buf, {
    content = 'round trip test',
    location_type = 'line',
    line_start = 0,
    line_end = 0,
  })

  -- Save
  store.save(buf)

  -- Verify file was written
  local filepath = '/tmp/gloss_test_roundtrip.md'
  expect.equality(store.has_gloss_file(filepath), true)

  -- Clear in-memory state
  annotation.clear(buf)
  expect.equality(annotation.list(buf), nil)

  -- Load back
  store.load(buf, filepath)
  local loaded = annotation.list(buf)
  expect.equality(#loaded, 1)
  expect.equality(loaded[1].content, 'round trip test')
  expect.equality(loaded[1].location_type, 'line')
  expect.equality(loaded[1].line_start, 0)

  annotation.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['setup']['save() removes file when no annotations remain'] = function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'line one' })
  vim.api.nvim_buf_set_name(buf, '/tmp/gloss_test_empty.md')

  local ann = annotation.create(buf, {
    content = 'will be deleted',
    location_type = 'line',
    line_start = 0,
    line_end = 0,
  })

  store.save(buf)
  local filepath = '/tmp/gloss_test_empty.md'
  expect.equality(store.has_gloss_file(filepath), true)

  -- Delete annotation and save again
  annotation.delete(buf, ann.id)
  store.save(buf)
  expect.equality(store.has_gloss_file(filepath), false)

  annotation.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

return T

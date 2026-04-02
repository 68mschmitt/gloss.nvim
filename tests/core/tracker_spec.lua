--- Tests for gloss.core.tracker

local new_set = MiniTest.new_set
local expect = MiniTest.expect

local T = new_set()

local tracker = require('gloss.core.tracker')
local annotation = require('gloss.core.annotation')
local config = require('gloss.config')

T['setup'] = new_set({
  hooks = {
    pre_case = function()
      config.setup({
        state_dir = vim.fn.tempname() .. '_gloss_test',
      })
    end,
  },
})

-- Helper
local function make_buffer(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

T['setup']['reconcile() keeps position when hash matches'] = function()
  local buf = make_buffer({ 'alpha', 'beta', 'gamma' })

  -- Create annotation on line 1 ("beta")
  local ann = annotation.create(buf, {
    content = 'note on beta',
    location_type = 'line',
    line_start = 1,
    line_end = 1,
  })
  local original_hash = ann.content_hash

  -- Reconcile — content hasn't changed, position should stay
  tracker.reconcile(buf, annotation)

  local found = annotation.find_by_id(buf, ann.id)
  expect.equality(found.line_start, 1)
  expect.equality(found.content_hash, original_hash)

  annotation.clear(buf)
  tracker.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['setup']['reconcile() finds content at new position'] = function()
  local buf = make_buffer({ 'alpha', 'beta', 'gamma' })

  -- Create annotation on line 1 ("beta")
  local ann = annotation.create(buf, {
    content = 'note on beta',
    location_type = 'line',
    line_start = 1,
    line_end = 1,
  })
  local original_hash = ann.content_hash

  -- Simulate content moving: insert a line before "beta"
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { 'new first line' })
  -- Now buffer is: "new first line", "alpha", "beta", "gamma"
  -- "beta" moved from line 1 to line 2, but annotation still says line 1

  -- Reconcile should find "beta" at line 2
  tracker.reconcile(buf, annotation)

  local found = annotation.find_by_id(buf, ann.id)
  expect.equality(found.line_start, 2)

  annotation.clear(buf)
  tracker.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['setup']['reconcile() falls back to line 0 when content is gone'] = function()
  local buf = make_buffer({ 'alpha', 'beta', 'gamma' })

  -- Create annotation on line 1 ("beta")
  local ann = annotation.create(buf, {
    content = 'note on beta',
    location_type = 'line',
    line_start = 1,
    line_end = 1,
  })

  -- Remove "beta" from the buffer entirely
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'completely', 'different', 'content' })

  -- Reconcile should fall back to line 0
  tracker.reconcile(buf, annotation)

  local found = annotation.find_by_id(buf, ann.id)
  expect.equality(found.line_start, 0)

  annotation.clear(buf)
  tracker.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['setup']['place_extmarks() sets extmark ids on annotations'] = function()
  local buf = make_buffer({ 'line one', 'line two' })

  annotation.create(buf, { content = 'test', location_type = 'line', line_start = 0, line_end = 0 })
  annotation.create(
    buf,
    { content = 'test2', location_type = 'line', line_start = 1, line_end = 1 }
  )

  tracker.place_extmarks(buf, annotation)

  local list = annotation.list(buf)
  for _, ann in ipairs(list) do
    expect.equality(type(ann.extmark_id), 'number')
  end

  annotation.clear(buf)
  tracker.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['setup']['sync_from_extmarks() updates positions from extmarks'] = function()
  local buf = make_buffer({ 'alpha', 'beta', 'gamma' })

  annotation.create(
    buf,
    { content = 'track me', location_type = 'line', line_start = 1, line_end = 1 }
  )

  tracker.place_extmarks(buf, annotation)

  -- Insert a line at the top — extmark should move
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { 'inserted' })

  tracker.sync_from_extmarks(buf, annotation)

  local list = annotation.list(buf)
  -- Extmark at line 1 should have moved to line 2
  expect.equality(list[1].line_start, 2)

  annotation.clear(buf)
  tracker.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

return T

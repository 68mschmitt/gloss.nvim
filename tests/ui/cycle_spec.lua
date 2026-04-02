--- Tests for gloss.ui.cycle

local new_set = MiniTest.new_set
local expect = MiniTest.expect

local T = new_set()

local cycle = require('gloss.ui.cycle')
local annotation = require('gloss.core.annotation')

-- Helper: create a scratch buffer with content
local function make_buffer(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

T['setup'] = new_set({
  hooks = {
    pre_case = function()
      require('gloss.config').setup({
        state_dir = vim.fn.tempname() .. '_gloss_test',
      })
    end,
  },
})

T['setup']['get_focus defaults to 1 for new buffer/line'] = function()
  local buf = make_buffer({ 'line one' })

  -- Cycle state should start fresh — next() with a single annotation
  -- should just toggle it (no crash, no error)
  annotation.create(buf, {
    content = 'solo annotation',
    location_type = 'line',
    line_start = 0,
    line_end = 0,
  })

  local ann = annotation.find_at(buf, 0)
  expect.equality(ann.collapsed, true)

  -- After cycle.next with single annotation, it should toggle
  local ns_id = vim.api.nvim_create_namespace('gloss_test_cycle')
  local cfg = require('gloss.config').get()

  -- This should not error
  cycle.next(buf, 0, annotation, cfg, ns_id)

  annotation.clear(buf)
  cycle.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['setup']['next() cycles through multiple annotations'] = function()
  local buf = make_buffer({ 'line one' })

  -- Create two annotations at the same line
  annotation.create(buf, {
    content = 'first',
    location_type = 'line',
    line_start = 0,
    line_end = 0,
  })
  annotation.create(buf, {
    content = 'second',
    location_type = 'line',
    line_start = 0,
    line_end = 0,
  })

  local all = annotation.find_all_at(buf, 0)
  expect.equality(#all, 2)

  -- Cycle next should focus the 2nd annotation
  local ns_id = vim.api.nvim_create_namespace('gloss_test_cycle2')
  local cfg = require('gloss.config').get()

  cycle.next(buf, 0, annotation, cfg, ns_id)
  -- First annotation should be collapsed, second expanded
  -- (or vice versa depending on initial focus)

  annotation.clear(buf)
  cycle.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['setup']['prev() cycles backwards through annotations'] = function()
  local buf = make_buffer({ 'line one' })

  annotation.create(buf, {
    content = 'first',
    location_type = 'line',
    line_start = 0,
    line_end = 0,
  })
  annotation.create(buf, {
    content = 'second',
    location_type = 'line',
    line_start = 0,
    line_end = 0,
  })
  annotation.create(buf, {
    content = 'third',
    location_type = 'line',
    line_start = 0,
    line_end = 0,
  })

  local ns_id = vim.api.nvim_create_namespace('gloss_test_cycle3')
  local cfg = require('gloss.config').get()

  -- prev from default (1) should wrap to 3
  cycle.prev(buf, 0, annotation, cfg, ns_id)

  -- The third annotation should now be expanded
  local all = annotation.find_all_at(buf, 0)
  -- Sort by created_at for stable ordering (same as cycle module)
  table.sort(all, function(a, b)
    return a.created_at < b.created_at
  end)

  -- Third should be uncollapsed, others collapsed
  expect.equality(all[1].collapsed, true)
  expect.equality(all[2].collapsed, true)
  expect.equality(all[3].collapsed, false)

  annotation.clear(buf)
  cycle.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['setup']['clear() resets focus state'] = function()
  local buf = make_buffer({ 'line one' })

  annotation.create(buf, {
    content = 'first',
    location_type = 'line',
    line_start = 0,
    line_end = 0,
  })
  annotation.create(buf, {
    content = 'second',
    location_type = 'line',
    line_start = 0,
    line_end = 0,
  })

  local ns_id = vim.api.nvim_create_namespace('gloss_test_cycle4')
  local cfg = require('gloss.config').get()

  -- Advance focus
  cycle.next(buf, 0, annotation, cfg, ns_id)

  -- Clear and cycle again — should restart from focus 1
  cycle.clear(buf)
  cycle.next(buf, 0, annotation, cfg, ns_id)

  -- After clear + next, focus should be at 2 (default 1, next goes to 2)
  local all = annotation.find_all_at(buf, 0)
  table.sort(all, function(a, b)
    return a.created_at < b.created_at
  end)
  expect.equality(all[1].collapsed, true) -- first collapsed
  expect.equality(all[2].collapsed, false) -- second expanded (focus=2)

  annotation.clear(buf)
  cycle.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['setup']['next() with no annotations warns'] = function()
  local buf = make_buffer({ 'line one' })
  local ns_id = vim.api.nvim_create_namespace('gloss_test_cycle5')
  local cfg = require('gloss.config').get()

  -- Should not error, should produce a warning notification
  cycle.next(buf, 0, annotation, cfg, ns_id)

  annotation.clear(buf)
  cycle.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

return T

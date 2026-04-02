--- Tests for gloss.core.annotation

local new_set = MiniTest.new_set
local expect = MiniTest.expect

local T = new_set()

local annotation = require('gloss.core.annotation')

-- Helper: create a scratch buffer with content
local function make_buffer(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

-- Helper: clean up after each test
T['setup'] = new_set({
  hooks = {
    pre_case = function()
      -- Seed random for reproducible IDs in tests
      math.randomseed(12345)
    end,
  },
})

T['setup']['create() returns annotation with all fields'] = function()
  local buf = make_buffer({ 'line one', 'line two', 'line three' })

  local ann = annotation.create(buf, {
    content = 'test annotation',
    location_type = 'line',
    line_start = 0,
    line_end = 0,
  })

  expect.equality(type(ann.id), 'string')
  expect.equality(ann.content, 'test annotation')
  expect.equality(ann.location_type, 'line')
  expect.equality(ann.line_start, 0)
  expect.equality(ann.line_end, 0)
  expect.equality(ann.col_start, nil)
  expect.equality(ann.col_end, nil)
  expect.equality(ann.collapsed, true) -- starts collapsed
  expect.equality(type(ann.content_hash), 'string')
  expect.equality(type(ann.created_at), 'string')

  annotation.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['setup']['list() returns all annotations for a buffer'] = function()
  local buf = make_buffer({ 'line one', 'line two' })

  annotation.create(
    buf,
    { content = 'first', location_type = 'line', line_start = 0, line_end = 0 }
  )
  annotation.create(
    buf,
    { content = 'second', location_type = 'line', line_start = 1, line_end = 1 }
  )

  local list = annotation.list(buf)
  expect.equality(#list, 2)
  expect.equality(list[1].content, 'first')
  expect.equality(list[2].content, 'second')

  annotation.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['setup']['find_at() returns annotation at given line'] = function()
  local buf = make_buffer({ 'line one', 'line two', 'line three' })

  annotation.create(
    buf,
    { content = 'on line 1', location_type = 'line', line_start = 1, line_end = 1 }
  )

  local found = annotation.find_at(buf, 1)
  expect.equality(found.content, 'on line 1')

  local not_found = annotation.find_at(buf, 0)
  expect.equality(not_found, nil)

  annotation.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['setup']['find_at() matches range annotations'] = function()
  local buf = make_buffer({ 'line one', 'line two', 'line three', 'line four' })

  annotation.create(
    buf,
    { content = 'range note', location_type = 'range', line_start = 1, line_end = 2 }
  )

  -- Should find annotation at both lines in the range
  expect.equality(annotation.find_at(buf, 1).content, 'range note')
  expect.equality(annotation.find_at(buf, 2).content, 'range note')
  -- Should not find at lines outside the range
  expect.equality(annotation.find_at(buf, 0), nil)
  expect.equality(annotation.find_at(buf, 3), nil)

  annotation.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['setup']['find_all_at() returns multiple annotations at same line'] = function()
  local buf = make_buffer({ 'line one' })

  annotation.create(
    buf,
    { content = 'first', location_type = 'line', line_start = 0, line_end = 0 }
  )
  annotation.create(
    buf,
    { content = 'second', location_type = 'line', line_start = 0, line_end = 0 }
  )

  local all = annotation.find_all_at(buf, 0)
  expect.equality(#all, 2)

  annotation.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['setup']['delete() removes annotation by id'] = function()
  local buf = make_buffer({ 'line one' })

  local ann = annotation.create(
    buf,
    { content = 'to delete', location_type = 'line', line_start = 0, line_end = 0 }
  )

  expect.equality(#annotation.list(buf), 1)

  local deleted = annotation.delete(buf, ann.id)
  expect.equality(deleted, true)
  expect.equality(#annotation.list(buf), 0)

  -- Deleting non-existent returns false
  local not_deleted = annotation.delete(buf, 'nonexistent')
  expect.equality(not_deleted, false)

  annotation.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['setup']['set_collapsed() toggles collapse state'] = function()
  local buf = make_buffer({ 'line one' })

  local ann = annotation.create(
    buf,
    { content = 'toggle me', location_type = 'line', line_start = 0, line_end = 0 }
  )
  expect.equality(ann.collapsed, true)

  annotation.set_collapsed(buf, ann.id, false)
  local found = annotation.find_by_id(buf, ann.id)
  expect.equality(found.collapsed, false)

  annotation.set_collapsed(buf, ann.id, true)
  found = annotation.find_by_id(buf, ann.id)
  expect.equality(found.collapsed, true)

  annotation.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['setup']['compute_hash() produces consistent hashes'] = function()
  local buf = make_buffer({ 'hello world', 'second line' })

  local hash1 = annotation.compute_hash(buf, 0, 0)
  local hash2 = annotation.compute_hash(buf, 0, 0)
  expect.equality(hash1, hash2)

  -- Different content = different hash
  local hash3 = annotation.compute_hash(buf, 1, 1)
  expect.no_equality(hash1, hash3)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T['setup']['serialize() strips runtime fields'] = function()
  local buf = make_buffer({ 'line one' })

  local ann = annotation.create(
    buf,
    { content = 'serialize me', location_type = 'line', line_start = 0, line_end = 0 }
  )
  ann.extmark_id = 42 -- simulate runtime field

  local serialized = annotation.serialize(buf)
  expect.equality(#serialized, 1)
  expect.equality(serialized[1].extmark_id, nil)
  expect.equality(serialized[1].content, 'serialize me')

  annotation.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T['setup']['update_position() modifies line positions'] = function()
  local buf = make_buffer({ 'a', 'b', 'c', 'd' })

  local ann = annotation.create(
    buf,
    { content = 'movable', location_type = 'line', line_start = 0, line_end = 0 }
  )

  annotation.update_position(buf, ann.id, 2, 2)
  local found = annotation.find_by_id(buf, ann.id)
  expect.equality(found.line_start, 2)
  expect.equality(found.line_end, 2)

  annotation.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

return T

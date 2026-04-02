# Contributing to gloss.nvim

## Quick Start

```bash
git clone https://github.com/your-handle/gloss.nvim.git
cd gloss.nvim
make test      # runs mini.test suite
make lint      # runs StyLua check
```

## Requirements

- Neovim >= 0.12
- [StyLua](https://github.com/JohnnyMorganz/StyLua) (for formatting)
- [mini.test](https://github.com/echasnovski/mini.test) (clone into `deps/mini.test`)
- make

Install StyLua:

```bash
cargo install stylua
```

Set up mini.test for local development:

```bash
mkdir -p deps
git clone --depth 1 https://github.com/echasnovski/mini.test deps/mini.test
```

## Project Structure

```
lua/gloss/
  init.lua          -- Entry point, setup()
  config.lua        -- Config schema and defaults
  health.lua        -- :checkhealth integration
  commands.lua      -- Command definitions and dispatch
  core/
    annotation.lua  -- Annotation data model and CRUD
    store.lua       -- JSON persistence and index file
    tracker.lua     -- Content hash + extmark position tracking
  ui/
    signs.lua       -- Sign column management
    highlights.lua  -- Highlight group management
    float.lua       -- Floating window display and scrolling
    cycle.lua       -- Overlap detection and cycling
plugin/
  gloss.lua         -- Lazy-load command stubs
tests/
  minimal_init.lua  -- Minimal nvim config for test runner
  core/             -- Unit tests for core modules
```

## Development Workflow

1. Create a branch from `main`
2. Make your changes
3. Run `make format` to auto-format
4. Run `make check` to verify formatting
5. Run `make test` to verify all tests pass
6. If you added a feature, add tests in `tests/`
7. Open a PR against `main`

CI runs `make ci` (format check + lint + tests). PRs that fail CI will
not be merged.

## Writing Tests

Tests use [mini.test](https://github.com/echasnovski/mini.test). Place
test files in `tests/` mirroring the source structure, with a `_spec.lua`
suffix.

Example pattern:

```lua
local new_set = MiniTest.new_set
local expect = MiniTest.expect

local T = new_set()

T['setup'] = new_set({
  hooks = {
    pre_case = function()
      -- per-test setup
    end,
  },
})

T['setup']['creates annotation with correct fields'] = function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'test line' })

  local annotation = require('gloss.core.annotation')
  local ann = annotation.create(buf, {
    content = 'test',
    location_type = 'line',
    line_start = 0,
    line_end = 0,
  })

  expect.equality(ann.content, 'test')

  annotation.clear(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

return T
```

Run all tests:

```bash
make test
```

## Style

- StyLua handles formatting -- see `.stylua.toml`
- Use LuaCATS annotations (`---@param`, `---@return`, etc.) for public functions
- Module-local functions are `local function name()`, not `M._name()`
- Prefer `vim.api` and `vim.json` over `vim.fn` wrappers where possible

## Commit Messages

Use conventional commits:

```
feat: add word-level annotation support
fix: handle empty buffer in tracker reconcile
test: add store round-trip tests
docs: update config options in README
```

## What Makes a Good PR

- **Focused**: one thing per PR
- **Tested**: new behavior has tests
- **Linted**: `make check` passes

## Questions?

Open an issue.

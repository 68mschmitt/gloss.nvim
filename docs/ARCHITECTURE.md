# gloss.nvim — Architecture

## Directory Structure

```
gloss.nvim/
├── .github/
│   └── workflows/
│       └── ci.yml
├── .gitignore
├── .stylua.toml
├── Makefile
├── docs/
│   ├── DESIGN.md
│   └── ARCHITECTURE.md
├── lua/
│   └── gloss/
│       ├── init.lua          -- Plugin entry point, setup(), command registration
│       ├── config.lua        -- Default config, user config merging
│       ├── health.lua        -- :checkhealth gloss
│       ├── commands.lua      -- Command definitions and dispatch
│       ├── core/
│       │   ├── annotation.lua    -- Annotation CRUD operations
│       │   ├── tracker.lua       -- Content hash + line tracking logic
│       │   └── store.lua         -- JSON read/write, index file management
│       └── ui/
│           ├── signs.lua         -- Gutter icon management
│           ├── highlights.lua    -- Referenced text highlighting
│           ├── float.lua         -- Floating window rendering and scrolling
│           └── cycle.lua         -- Overlap detection and cycling logic
├── plugin/
│   └── gloss.lua             -- Lazy-load trigger
└── tests/
    ├── minimal_init.lua      -- Minimal neovim config for test runner
    ├── harness.lua           -- Test utilities
    ├── runner.lua            -- Test runner entry point
    └── core/
        ├── annotation_spec.lua
        ├── tracker_spec.lua
        └── store_spec.lua
```

## Module Responsibilities

### `gloss.init`
- `setup(opts)` — merges user config, registers commands, sets up autocommands
- Single entry point for the plugin

### `gloss.config`
- Defines defaults (state dir, gutter icon, highlight group, etc.)
- Validates and merges user-provided options

### `gloss.commands`
- Maps user-facing commands to core operations:
  - `:GlossAdd` — add annotation at current location
  - `:GlossDelete` — delete annotation under cursor
  - `:GlossToggle` — toggle annotation under cursor
  - `:GlossToggleAll` — toggle all annotations in current buffer
  - `:GlossNext` / `:GlossPrev` — cycle overlapping annotations
  - `:GlossAttach` — open selection menu to attach a gloss file

### `gloss.core.annotation`
- Annotation data model (create, read, update, delete)
- Each annotation contains:
  - `id` — unique identifier (UUID or incrementing)
  - `content` — markdown string
  - `location` — type (`line`, `word`, `range`) + position data
  - `content_hash` — hash of the referenced buffer text at creation time
  - `line_start` — first line of the reference (0-indexed)
  - `line_end` — last line of the reference (0-indexed, same as start for single line)
  - `col_start` — column start (for word-level annotations, nil otherwise)
  - `col_end` — column end (for word-level annotations, nil otherwise)
  - `collapsed` — boolean, current display state
  - `created_at` — timestamp

### `gloss.core.tracker`
- On buffer load: reconcile stored annotations with current buffer content
  1. For each annotation, check if `content_hash` matches text at `line_start`
  2. If no match, search nearby lines (expanding window) for matching hash
  3. If found elsewhere, update `line_start`/`line_end`
  4. If not found, reset to line 0
- Uses neovim extmarks (`nvim_buf_set_extmark`) to track positions during editing
- On buffer write: update stored line numbers from extmark positions

### `gloss.core.store`
- Read/write gloss files (JSON)
- Manage the index file (`<state_dir>/gloss/index.json`)
  - Maps absolute file paths → gloss file paths
  - Updated when user attaches a gloss file manually
- Default gloss file path: `<state_dir>/gloss/<hashed_filepath>.json`

### `gloss.ui.signs`
- Register and place sign column icons via `nvim_buf_set_extmark` with `sign_text`
- One icon per annotation on its first referenced line

### `gloss.ui.highlights`
- Apply highlight groups to referenced text
- Line-level: full line highlight
- Word-level: column range highlight
- Range-level: multi-line highlight

### `gloss.ui.float`
- Create and manage floating windows for expanded annotations
- Render markdown content
- Handle scrolling within the float
- Position relative to the annotation's referenced location

### `gloss.ui.cycle`
- Detect when multiple annotations overlap or are near each other
- Track which annotation is "focused" at a given position
- `:GlossNext` / `:GlossPrev` rotate the focused annotation

## Data Flow

```
User action (command)
    │
    ▼
commands.lua — dispatch
    │
    ├──► core/annotation.lua — CRUD
    │        │
    │        ▼
    │    core/store.lua — persist to JSON
    │
    └──► ui/* — update signs, highlights, floats
```

```
Buffer load
    │
    ▼
core/store.lua — read gloss file
    │
    ▼
core/tracker.lua — reconcile positions (hash + line check)
    │
    ▼
core/annotation.lua — update annotation positions
    │
    ├──► ui/signs.lua — place gutter icons
    └──► ui/highlights.lua — apply highlights
```

```
Buffer write
    │
    ▼
core/tracker.lua — read extmark positions
    │
    ▼
core/annotation.lua — update line numbers from extmarks
    │
    ▼
core/store.lua — write gloss file
```

## Gloss File Format

```json
{
  "version": 1,
  "file": "/absolute/path/to/source/file.md",
  "annotations": [
    {
      "id": "a1b2c3",
      "content": "This function handles the edge case where...",
      "location_type": "range",
      "line_start": 10,
      "line_end": 15,
      "col_start": null,
      "col_end": null,
      "content_hash": "sha256:abcdef1234567890",
      "collapsed": false,
      "created_at": "2026-04-01T12:00:00Z"
    }
  ]
}
```

## Index File Format

```json
{
  "version": 1,
  "mappings": {
    "/absolute/path/to/file.md": "/path/to/custom/gloss.json",
    "/another/file.lua": "<state_dir>/gloss/a3f8c1.json"
  }
}
```

## Key Design Decisions

1. **Extmarks as the source of truth during editing** — while the buffer is
   open, extmarks track position. On write, we sync extmark positions back
   to the annotation data and persist. On load, we reconcile from stored
   data using the hash+line strategy.

2. **Hashed filepath for default gloss file names** — avoids filesystem
   path issues (slashes, length) while keeping a 1:1 mapping.

3. **Version field in JSON** — allows future migration of the storage
   format without breaking existing gloss files.

4. **No default keybindings** — the plugin exposes commands only. Users
   bind them however they want. This respects diverse config styles and
   avoids conflicts.

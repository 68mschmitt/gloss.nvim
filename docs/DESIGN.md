# gloss.nvim — Design

## Problem

Adding context to notes without cluttering the note itself or creating
separate files with hard-to-find links. There is no clean way to annotate
a buffer in neovim — to say "here is what I was thinking about this block"
without polluting the text.

## Domain

| Concept    | Definition                                                        |
|------------|-------------------------------------------------------------------|
| Buffer     | A neovim buffer containing text the user wants to annotate.       |
| Annotation | A markdown note attached to a specific location in a buffer.      |
| Location   | A line, word(s) on a line, or range of lines in a buffer.         |
| Extmark    | Neovim's API for tracking positions in a buffer across edits.     |
| Gloss file | A JSON file that persists annotations for a given buffer.         |
| Index file | A JSON file mapping buffers to their gloss files.                 |

## Functional Requirements

The user can:

- **Add** an annotation to:
  - A specific line in a buffer
  - A word or words on a line in a buffer
  - A range of lines in a buffer
- **Delete** an annotation
- **Collapse** an annotation (hide the floating content, keep the gutter icon)
- **Expand** an annotation (show the floating content)
- **Toggle** all annotations for a buffer (hide/show)
- **Attach** a gloss file to any buffer via a selection menu
- **Cycle** between overlapping annotations when multiple exist at or near
  the same screen position

## Non-Functional Requirements

- Annotations persist across sessions via JSON gloss files
- Default storage location: neovim state directory (`vim.fn.stdpath("state")`)
- Storage location is configurable
- Manual buffer-to-gloss-file mappings persist in an index file (set-and-forget)
- Annotations track their referenced text using both line number and content hash
- Best-effort location tracking when the buffer changes:
  1. Check stored line number for matching content hash (fast path)
  2. Search nearby lines for matching hash (slow path)
  3. Fall back to line 0 if content is gone entirely

## Constraints

- Neovim plugin
- Written in ~100% Lua
- Must contain tests
- CI/CD via GitHub Actions
- Linting enforced
- Makefile for running tests and linting

## UI Specification

### Collapsed State
- Gutter icon (sign column) on the first line of the referenced location
- Subtle highlight on the referenced text (line, word(s), or range)

### Expanded State
- Floating window displaying the annotation content (markdown)
- Floating window must support scrolling (annotations have no length limit)
- Gutter icon and highlight remain visible

### Overlap Behavior
- When multiple annotations fit on screen simultaneously, show them side by side
- When they cannot fit, show one at a time and let the user cycle between them

### Stacking
- Multiple annotations can exist on the same line or overlapping ranges
- Each gets its own gutter icon; cycling navigates between them

### Interaction Model
- All functionality exposed via commands (`:Gloss*`)
- The plugin does **not** define default keybindings
- The user maps commands to keys in their own config

## Annotation Format

- Content: Markdown, 1 to many lines, no length limit
- Can contain anything valid in markdown (prose, code blocks, links, etc.)

## Scope Boundaries

- Buffer-local only. No cross-file annotation references.
- Annotations cannot reference other annotations.
- No plans for cross-file features in v1.

## Trade-offs

| Decision                              | Rationale                                    |
|---------------------------------------|----------------------------------------------|
| JSON over SQLite                      | Simpler, human-readable, easy to debug.      |
| Content hash + line number tracking   | Balances accuracy with performance.           |
| Fall back to line 0 on lost reference | Predictable behavior over silent failure.     |
| No default keybindings                | Respects user autonomy and config style.      |
| Commands-first interaction            | Discoverable, scriptable, composable.         |

## Risks

| Risk                                  | Mitigation                                   |
|---------------------------------------|----------------------------------------------|
| UI becomes cluttered                  | Collapse/toggle, subtle highlights, cycling. |
| Not ergonomic to use                  | Commands-only, user-defined bindings.        |
| Annotations not helpful               | Markdown support, no length limit.           |
| State is lost                         | JSON persistence, index file for mappings.   |
| Annotation references wrong location  | Dual tracking (hash + line), fallback logic. |

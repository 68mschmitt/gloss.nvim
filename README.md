# gloss.nvim

Attach markdown annotations to specific locations in any buffer, persisted across sessions.

<!-- TODO: Add demo GIF showing basic add/toggle workflow -->

## Requirements

- Neovim >= 0.12

No external dependencies.

## Install

### lazy.nvim

```lua
{
  "68mschmitt/gloss.nvim",
  cmd = {
    "GlossAdd", "GlossDelete", "GlossEdit", "GlossToggle",
    "GlossToggleAll", "GlossNext", "GlossPrev", "GlossAttach",
    "GlossList",
  },
  keys = {
    { "<leader>ga", "<cmd>GlossAdd<cr>", mode = { "n", "v" }, desc = "Add gloss" },
    { "<leader>gd", "<cmd>GlossDelete<cr>", desc = "Delete gloss" },
    { "<leader>ge", "<cmd>GlossEdit<cr>", desc = "Edit gloss" },
    { "<leader>gt", "<cmd>GlossToggle<cr>", desc = "Toggle gloss" },
    { "<leader>gT", "<cmd>GlossToggleAll<cr>", desc = "Toggle all glosses" },
    { "<leader>gn", "<cmd>GlossNext<cr>", desc = "Next gloss" },
    { "<leader>gp", "<cmd>GlossPrev<cr>", desc = "Previous gloss" },
    { "<leader>gl", "<cmd>GlossList<cr>", desc = "List glosses" },
  },
  opts = {},
}
```

### mini.deps

```lua
MiniDeps.add({ source = "68mschmitt/gloss.nvim" })
require("gloss").setup()
```

### Manual

```bash
git clone https://github.com/68mschmitt/gloss.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/gloss.nvim
```

Then add `require("gloss").setup()` to your config.

## Usage

Select text (or place your cursor on a line), run `:GlossAdd`, write
markdown in the scratch buffer that opens, and `:w` to save. A sign
appears in the gutter. `:GlossToggle` expands or collapses the
annotation under the cursor. `:GlossToggleAll` hides or shows all
annotations in the buffer.

| Command           | Description                                       |
|-------------------|---------------------------------------------------|
| `:GlossAdd`       | Add annotation at cursor or visual selection      |
| `:GlossDelete`    | Delete annotation under cursor                    |
| `:GlossEdit`      | Edit annotation under cursor                      |
| `:GlossToggle`    | Toggle annotation under cursor                    |
| `:GlossToggleAll` | Toggle all annotations in current buffer          |
| `:GlossNext`      | Cycle to next overlapping annotation              |
| `:GlossPrev`      | Cycle to previous overlapping annotation          |
| `:GlossAttach`    | Attach a gloss file to the current buffer         |
| `:GlossList`      | List all annotations in the quickfix list         |

### Suggested keymaps

The plugin does not define default keybindings. Map them however you want:

```lua
vim.keymap.set({ "n", "v" }, "<leader>ga", "<cmd>GlossAdd<cr>", { desc = "Add gloss" })
vim.keymap.set("n", "<leader>gd", "<cmd>GlossDelete<cr>", { desc = "Delete gloss" })
vim.keymap.set("n", "<leader>ge", "<cmd>GlossEdit<cr>", { desc = "Edit gloss" })
vim.keymap.set("n", "<leader>gt", "<cmd>GlossToggle<cr>", { desc = "Toggle gloss" })
vim.keymap.set("n", "<leader>gT", "<cmd>GlossToggleAll<cr>", { desc = "Toggle all glosses" })
vim.keymap.set("n", "<leader>gn", "<cmd>GlossNext<cr>", { desc = "Next gloss" })
vim.keymap.set("n", "<leader>gp", "<cmd>GlossPrev<cr>", { desc = "Previous gloss" })
vim.keymap.set("n", "<leader>gl", "<cmd>GlossList<cr>", { desc = "List glosses" })
```

## Configuration

```lua
require("gloss").setup({
  -- Directory for gloss files and index
  state_dir = vim.fn.stdpath("state") .. "/gloss",
  -- Gutter icon (1-2 chars)
  sign_text = "",
  -- Highlight group for the sign
  sign_hl = "GlossSign",
  -- Highlight group for annotated text
  hl_group = "GlossHighlight",
  -- Border style for floating windows
  float_border = "rounded",
  -- Maximum width of annotation floats
  float_max_width = 60,
  -- Maximum height of annotation floats
  float_max_height = 20,
  -- Height of the scratch buffer split for editing
  edit_height = 10,
})
```

All values shown are defaults. Pass only what you want to change.

## Highlight Groups

| Group                  | Default                              | Description                  |
|------------------------|--------------------------------------|------------------------------|
| `GlossSign`            | `fg=#7aa2f7, bold`                   | Sign column icon             |
| `GlossHighlight`       | `underline, sp=#FFFF00`              | Annotated text (collapsed)   |
| `GlossHighlightActive` | `underline, sp=#7aa2f7, bg=#1a1b2e` | Annotated text (expanded)    |

Override with:

```lua
vim.api.nvim_set_hl(0, "GlossSign", { fg = "#e0af68" })
```

## How It Works

Annotations are stored as JSON in `state_dir`, one file per source file
(named by a hash of the file path). Location tracking uses content
hashing combined with line numbers. When you reopen a file, gloss
reconciles stored positions against the current buffer content using an
expanding-window search. If the annotated text moved, gloss finds it. If
it was deleted entirely, the annotation falls back to line 0.

## Health Check

```vim
:checkhealth gloss
```

## License

[MIT](LICENSE)

# md-outline.nvim

A 40-column sidebar on the right showing the headers of the current markdown
buffer, with subheaders indented.

```
Project Title
  Installation
    With lazy.nvim
  Usage
    Configuration
Second Top
```

Requires Neovim 0.10+.

## Install

Use Neovim’s built-in package directory or vim.pack.

## Usage

| Command           | Action                |
| ----------------- | --------------------- |
| `:MdOutline`      | Toggle the outline    |
| `:MdOutlineOpen`  | Open the outline      |
| `:MdOutlineClose` | Close the outline     |

Inside the outline window:

| Key                       | Action                                   |
| ------------------------- | ---------------------------------------- |
| `<CR>` / double-click     | Jump to the header                       |
| `o`                       | Jump to the header, keep focus in outline |
| `r`                       | Refresh                                  |
| `q`                       | Close                                    |

The outline refreshes as you type, follows whichever markdown buffer you
switch to, and highlights the section your cursor is in.

Both ATX (`## Header`) and setext (`Header` underlined with `===`/`---`)
headers are recognised. Lines inside fenced code blocks and YAML front matter
are ignored.

## Configuration

Defaults:

```lua
require("md-outline").setup({
  width = 40,           -- width of the outline window
  indent = 2,           -- spaces of indent per header level
  follow_cursor = true, -- highlight the section the cursor is in
  auto_close = true,    -- close the outline when it is the last window left
  filetypes = { "markdown", "rmd", "quarto" },
})
```

Highlight groups `MdOutlineH1` … `MdOutlineH6` (linked to
`@markup.heading.N.markdown`) and `MdOutlineEmpty` can be overridden.

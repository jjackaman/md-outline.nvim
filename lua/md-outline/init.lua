-- md-outline.nvim: a sidebar showing the headers of the current markdown buffer.
local M = {}

M.config = {
  width = 40, -- width of the outline window
  indent = 2, -- spaces of indent per header level
  follow_cursor = true, -- highlight the section the cursor is in
  auto_close = true, -- close the outline when it is the last window left
  filetypes = { "markdown", "rmd", "quarto" },
}

local ns = vim.api.nvim_create_namespace("md_outline")
local augroup = vim.api.nvim_create_augroup("MdOutline", { clear = true })
local hl_augroup = vim.api.nvim_create_augroup("MdOutlineHighlights", { clear = true })

local state = {
  win = nil, -- outline window
  buf = nil, -- outline buffer
  src_buf = nil, -- markdown buffer being outlined
  src_win = nil, -- last window that showed src_buf
  items = {}, -- { level, text, lnum } for each outline line
}

local function valid_win(w)
  return w ~= nil and vim.api.nvim_win_is_valid(w)
end

local function valid_buf(b)
  return b ~= nil and vim.api.nvim_buf_is_valid(b)
end

local function is_markdown(buf)
  -- compound filetypes like "markdown.pandoc" count too
  local ft = vim.split(vim.bo[buf].filetype, ".", { plain = true })[1]
  return vim.tbl_contains(M.config.filetypes, ft)
end

local function set_highlights()
  for i = 1, 6 do
    vim.api.nvim_set_hl(0, "MdOutlineH" .. i, { link = "@markup.heading." .. i .. ".markdown", default = true })
  end
  vim.api.nvim_set_hl(0, "MdOutlineEmpty", { link = "Comment", default = true })
end

set_highlights()
vim.api.nvim_create_autocmd("ColorScheme", { group = hl_augroup, callback = set_highlights })

-- Strip the most common inline markup so the outline reads cleanly.
local function clean(text)
  text = text:gsub("%[(.-)%]%b()", "%1") -- [text](url)
  text = text:gsub("%[(.-)%]%b[]", "%1") -- [text][ref]
  text = text:gsub("%*%*", ""):gsub("__", ""):gsub("`", "")
  return vim.trim(text)
end

-- Is this line plain paragraph text (i.e. something a setext underline can turn into a header)?
local function is_paragraph(line)
  return line:match("%S")
    and not line:match("^    ") -- indented code
    and not line:match("^%s*#") -- ATX header
    and not line:match("^%s*>") -- blockquote
    and not line:match("^%s*[-*+]%s") -- bullet list
    and not line:match("^%s*%d+[.)]%s") -- ordered list
    and not line:match("^%s*[`~][`~][`~]") -- fence
    and not line:match("^%s*[-=*_%s]+$") -- rule / underline
end

--- Parse markdown lines into a list of headers.
---@param lines string[]
---@return { level: integer, text: string, lnum: integer }[]
function M.parse(lines)
  local items = {}
  local fence -- the opening fence while inside a fenced code block
  local start = 1

  -- skip YAML front matter
  if lines[1] and lines[1]:match("^%-%-%-%s*$") then
    for i = 2, #lines do
      if lines[i]:match("^%-%-%-%s*$") or lines[i]:match("^%.%.%.%s*$") then
        start = i + 1
        break
      end
    end
  end

  for i = start, #lines do
    local line = lines[i]
    local f = line:match("^ ? ? ?(```+)") or line:match("^ ? ? ?(~~~+)")
    if fence then
      if f and f:sub(1, 1) == fence:sub(1, 1) and #f >= #fence and line:match("^%s*[`~]+%s*$") then
        fence = nil
      end
    elseif f then
      fence = f
    else
      local hashes, text = line:match("^ ? ? ?(#+)%s+(.-)%s*$")
      if hashes and #hashes <= 6 then
        -- drop an optional closing sequence: "## Title ##"
        text = clean(text:gsub("%s+#+$", ""):gsub("^#+$", ""))
        if text ~= "" then
          table.insert(items, { level = #hashes, text = text, lnum = i })
        end
      elseif i > start and is_paragraph(lines[i - 1]) then
        -- setext headers: a line of text underlined with === or ---
        local level = (line:match("^ ? ? ?=+%s*$") and 1) or (line:match("^ ? ? ?%-+%s*$") and 2)
        if level then
          table.insert(items, { level = level, text = clean(lines[i - 1]), lnum = i - 1 })
        end
      end
    end
  end

  return items
end

-- Move the outline cursor to the header of the section `win`'s cursor is in.
local function sync_cursor(win)
  if not M.config.follow_cursor or not valid_win(state.win) or not valid_win(win) then
    return
  end
  if vim.api.nvim_win_get_buf(win) ~= state.src_buf or #state.items == 0 then
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(win)[1]
  local idx = 1
  for i, item in ipairs(state.items) do
    if item.lnum > lnum then
      break
    end
    idx = i
  end
  vim.api.nvim_win_set_cursor(state.win, { idx, 0 })
end

--- Re-parse the source buffer and redraw the outline.
function M.refresh()
  if not valid_buf(state.buf) then
    return
  end

  local items = {}
  if valid_buf(state.src_buf) then
    items = M.parse(vim.api.nvim_buf_get_lines(state.src_buf, 0, -1, false))
  end

  -- indent relative to the shallowest header, so a doc starting at ## isn't pushed right
  local min_level = math.huge
  for _, item in ipairs(items) do
    min_level = math.min(min_level, item.level)
  end

  local lines = {}
  for i, item in ipairs(items) do
    lines[i] = string.rep(" ", (item.level - min_level) * M.config.indent) .. item.text
  end
  if #items == 0 then
    lines = { "(no headers)" }
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for i, line in ipairs(lines) do
    local group = items[i] and ("MdOutlineH" .. items[i].level) or "MdOutlineEmpty"
    vim.api.nvim_buf_set_extmark(state.buf, ns, i - 1, 0, { end_col = #line, hl_group = group })
  end

  state.items = items
end

-- Jump to the header under the outline cursor. With `stay`, keep focus in the outline.
local function jump(stay)
  local item = state.items[vim.api.nvim_win_get_cursor(state.win)[1]]
  if not item or not valid_buf(state.src_buf) then
    return
  end

  local win = state.src_win
  if not valid_win(win) or vim.api.nvim_win_get_buf(win) ~= state.src_buf then
    win = vim.fn.bufwinid(state.src_buf)
  end
  if win == -1 then
    -- source buffer isn't visible anymore: reopen it to the left of the outline
    win = vim.api.nvim_open_win(state.src_buf, false, { split = "left", win = -1 })
    vim.api.nvim_win_set_width(state.win, M.config.width)
  end
  state.src_win = win

  vim.api.nvim_win_set_cursor(win, { item.lnum, 0 })
  vim.api.nvim_win_call(win, function()
    vim.cmd("normal! zvzt")
  end)
  if not stay then
    vim.api.nvim_set_current_win(win)
  end
end

local function cleanup()
  state.win, state.buf, state.items = nil, nil, {}
  vim.api.nvim_clear_autocmds({ group = augroup })
end

local function create_autocmds()
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function(args)
      if args.buf == state.buf or not is_markdown(args.buf) then
        return
      end
      state.src_win = vim.api.nvim_get_current_win()
      if args.buf ~= state.src_buf then
        state.src_buf = args.buf
        M.refresh()
      end
      sync_cursor(state.src_win)
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
    group = augroup,
    callback = function(args)
      if args.buf == state.src_buf then
        M.refresh()
        sync_cursor(vim.api.nvim_get_current_win())
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    callback = function(args)
      if args.buf == state.src_buf then
        sync_cursor(vim.api.nvim_get_current_win())
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = augroup,
    callback = function(args)
      if args.buf == state.src_buf then
        state.src_buf = nil
        vim.schedule(M.refresh)
      end
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    callback = function(args)
      if tonumber(args.match) == state.win then
        cleanup()
        return
      end
      if not M.config.auto_close then
        return
      end
      vim.schedule(function()
        if not valid_win(state.win) then
          return
        end
        local wins = vim.tbl_filter(function(w)
          return vim.api.nvim_win_get_config(w).relative == ""
        end, vim.api.nvim_tabpage_list_wins(0))
        if #wins == 1 and wins[1] == state.win then
          pcall(vim.cmd, #vim.api.nvim_list_tabpages() > 1 and "tabclose" or "quit")
        end
      end)
    end,
  })
end

--- Open the outline window for the current markdown buffer.
function M.open()
  if valid_win(state.win) then
    return
  end

  local cur_win, cur_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  if is_markdown(cur_buf) then
    state.src_buf, state.src_win = cur_buf, cur_win
  end
  if not valid_buf(state.src_buf) then
    vim.notify("md-outline: current buffer is not markdown", vim.log.levels.WARN)
    return
  end

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].filetype = "mdoutline"
  vim.bo[state.buf].modifiable = false

  state.win = vim.api.nvim_open_win(state.buf, false, { split = "right", win = -1, width = M.config.width })
  local wo = vim.wo[state.win]
  wo.winfixwidth = true
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.statuscolumn = ""
  wo.wrap = false
  wo.list = false
  wo.spell = false
  wo.cursorline = true
  if vim.fn.exists("+winfixbuf") == 1 then
    wo.winfixbuf = true
  end

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = state.buf, nowait = true, silent = true, desc = desc })
  end
  map("<CR>", function() jump(false) end, "Jump to header")
  map("<2-LeftMouse>", function() jump(false) end, "Jump to header")
  map("o", function() jump(true) end, "Preview header")
  map("r", M.refresh, "Refresh outline")
  map("q", M.close, "Close outline")

  create_autocmds()
  M.refresh()
  sync_cursor(state.src_win)
end

--- Close the outline window.
function M.close()
  if valid_win(state.win) then
    -- can't close the last window; leave it alone in that case
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  if not valid_win(state.win) then
    cleanup()
  end
end

--- Toggle the outline window.
function M.toggle()
  if valid_win(state.win) then
    M.close()
  else
    M.open()
  end
end

--- Optional: override defaults.
---@param opts table|nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

return M

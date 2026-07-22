--- blink-im-zhh: a blink.cmp source for Chinese input via the 虎码 (HuCode)
--- shape-based code table.

local source_mod = require("blink-im-zhh.source")
local table_utils = require("blink-im-zhh.table")

local M = {}

M.config = {
  enable = false,
  noice = true,
  maxn = 8,
  tables = nil,
  format = nil,
}

M.source_name = "IM"
M._init = false
M._enable_overridden = false

--- Merge user options into the shared config, in place.
function M.setup(opts)
  opts = opts or {}
  for k, v in pairs(opts) do
    M.config[k] = v
  end
end

--- Entry point called by blink.cmp.
function M.new(opts, config)
  opts = opts or {}
  if not M._init then
    local init_opts = vim.tbl_extend("force", {}, opts)
    if M._enable_overridden then
      init_opts.enable = nil
    end
    vim.tbl_deep_extend("force", M.config, init_opts)
    M._init = true
  end
  if config and config.name then
    M.source_name = config.name
  end
  return source_mod.new(M.config)
end

--- Enable/Disable the input method.
function M.toggle()
  if M.config.noice then
    local ok, noice = pcall(require, "noice")
    if ok and noice and noice.cmd then
      pcall(noice.cmd, "dismiss")
    end
  end
  M.config.enable = not M.config.enable
  M._enable_overridden = true
  -- 启用虎码时，以当前光标列为编码起点，避免把之前残留的字母拼进新编码
  if M.config.enable then
    M.config._insert_start = M.config._insert_start or {}
    M.config._insert_start[vim.api.nvim_get_current_buf()] = vim.api.nvim_win_get_cursor(0)[2]
  end
  vim.notify("虎码: " .. (M.config.enable and "已启动" or "已关闭"))
  return M.config.enable
end

function M.getStatus()
  return M.config.enable
end

function M.select()
  return function(fallback)
    if not (M.getStatus() and require("blink.cmp").is_visible()) then
      return fallback()
    end
    local ok, item = pcall(function()
      return require("blink.cmp.completion.list").get_selected_item()
    end)
    if ok and item and item.source_name == M.source_name then
      require("blink.cmp").accept()
      return
    end
    return fallback()
  end
end

function M.confirmEnter()
  return function(fallback)
    if M.getStatus() and require("blink.cmp").is_visible() then
      require("blink.cmp").cancel()
      return
    end
    return fallback()
  end
end

--- Insert a full-width Chinese punctuation string directly into the buffer at
--- the cursor. We use nvim_buf_set_text instead of nvim_feedkeys because feeding
--- multi-byte UTF-8 through the input parser was the cause of the garbled
--- output; writing the buffer directly is synchronous and avoids any race with
--- blink.cmp's accept() text edit (both edits run back-to-back in the same
--- scheduled tick, in a well-defined order).
---
--- `rhs` may contain literal "<Left>" markers (used by the auto-paired quotes to
--- center the cursor between the two quote characters). Each marker is stripped
--- from the inserted text and turned into a one-character cursor move to the
--- left, measured in bytes so full-width characters are handled correctly.
local function insert_punct(rhs)
  local left_moves = 0
  local text = rhs:gsub("<Left>", function()
    left_moves = left_moves + 1
    return ""
  end)

  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { text })

  --- nvim_buf_set_text does NOT move the window cursor: it stays at the
  --- insertion start (before the inserted text). Without an explicit forward
  --- step, the cursor would be stuck before the punctuation and every
  --- subsequent keystroke would prepend instead of append. So we first jump to
  --- the byte offset right after the inserted text, then apply any <Left>
  --- moves (auto-paired quotes) on top of that.
  local new_col = col + #text

  --- Each <Left> moves the cursor one character to the left. We compute the byte
  --- length of the character immediately to the left of the cursor so multi-byte
  --- UTF-8 (e.g. full-width quotes, 3 bytes each) is moved correctly. Neovim
  --- columns are 0-based byte offsets, while string:byte() is 1-based.
  for _ = 1, left_moves do
    if new_col <= 0 then
      break
    end
    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
    local i = new_col
    while i > 0 do
      local b = line:byte(i)
      if b == nil then
        break
      end
      if b < 0x80 or b >= 0xC0 then
        break
      end
      i = i - 1
    end
    local blen = new_col - i + 1
    new_col = math.max(0, new_col - blen)
  end

  vim.api.nvim_win_set_cursor(0, { row, new_col })
end

--- Chinese punctuation autocmd — intercepts punctuation keystrokes BEFORE they
--- are inserted. When IM is on and a punctuation key listed in
--- table_utils.chinese_symbol() is pressed:
---   1. If the blink menu is visible → accept the first candidate
---   2. Replace the character with the full-width Chinese version
---
--- Quote keys are handled separately: after accepting, we prevent the original
--- quote from being inserted and instead use feedkeys to insert the auto-paired
--- Chinese quotes with the cursor centered between them.
---
--- Uses InsertCharPre instead of keymaps because blink.cmp's completion menu
--- can interfere with insert-mode keymap dispatch timing.
vim.api.nvim_create_autocmd("InsertCharPre", {
  group = vim.api.nvim_create_augroup("BlinkImZhhPunctuation", { clear = true }),
  callback = function()
    if not M.config.enable then
      return
    end

    local char = vim.v.char
    local symbols = table_utils.chinese_symbol()
    local rhs = symbols[char]
    if not rhs then
      return
    end

    --- Suppress the original ASCII character. We defer everything below one
    --- event-loop tick so that blink.cmp's internal state is stable when we
    --- call accept() — calling it synchronously inside InsertCharPre often
    --- has no effect because blink has not finished processing yet.
    vim.v.char = ""

    vim.schedule(function()
      local blink = require("blink.cmp")
      if blink.is_visible() then
        --- accept() is asynchronous: the candidate text is written to the
        --- buffer (and the cursor repositioned to its end) only after the
        --- resolve chain completes. Passing insert_punct as the callback
        --- guarantees the punctuation is inserted AFTER `一` is in the buffer
        --- and the cursor sits right after it. Calling insert_punct right after
        --- accept() (as before) would insert `。` at the stale pre-accept cursor,
        --- then the async edit would shift it to `一|。`.
        blink.accept({ callback = function() insert_punct(rhs) end })
      else
        insert_punct(rhs)
      end
    end)
  end,
})

vim.api.nvim_create_user_command("BlinkImZhhToggle", function()
  M.toggle()
end, {})

--- 进入插入模式时记录光标列，作为虎码编码起点（配合 source.lua 的 boundary 处理）。
--- 这样离开插入模式、残留小写字母后重新进入时，新编码不会把旧字母拼进去。
vim.api.nvim_create_autocmd("InsertEnter", {
  group = vim.api.nvim_create_augroup("BlinkImZhhBoundary", { clear = true }),
  callback = function()
    if not M.config.enable then
      return
    end
    M.config._insert_start = M.config._insert_start or {}
    M.config._insert_start[vim.api.nvim_get_current_buf()] = vim.api.nvim_win_get_cursor(0)[2]
  end,
})

return M

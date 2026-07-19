--- blink-im-zhh: a blink.cmp source for Chinese input via the 虎码 (HuCode)
--- shape-based code table.

local source_mod = require('blink-im-zhh.source')
local table_utils = require('blink-im-zhh.table')

local M = {}

M.config = {
  enable = false,
  noice = true,
  maxn = 8,
  tables = nil,
  format = nil,
}

M.source_name = 'IM'
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
    local init_opts = vim.tbl_extend('force', {}, opts)
    if M._enable_overridden then
      init_opts.enable = nil
    end
    vim.tbl_deep_extend('force', M.config, init_opts)
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
    local ok, noice = pcall(require, 'noice')
    if ok and noice and noice.cmd then
      pcall(noice.cmd, 'dismiss')
    end
  end
  M.config.enable = not M.config.enable
  M._enable_overridden = true
  vim.notify('IM: ' .. (M.config.enable and 'on' or 'off'))
  return M.config.enable
end

function M.getStatus()
  return M.config.enable
end

function M.select()
  return function(fallback)
    if not (M.getStatus() and require('blink.cmp').is_visible()) then
      return fallback()
    end
    local ok, item = pcall(function()
      return require('blink.cmp.completion.list').get_selected_item()
    end)
    if ok and item and item.source_name == M.source_name then
      require('blink.cmp').accept()
      return
    end
    return fallback()
  end
end

function M.confirmEnter()
  return function(fallback)
    if M.getStatus() and require('blink.cmp').is_visible() then
      require('blink.cmp').cancel()
      return
    end
    return fallback()
  end
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
vim.api.nvim_create_autocmd('InsertCharPre', {
  group = vim.api.nvim_create_augroup('BlinkImZhhPunctuation', { clear = true }),
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
    vim.v.char = ''

    vim.schedule(function()
      local blink = require('blink.cmp')
      if blink.is_visible() then
        blink.accept()
      end

      -- Insert the full-width Chinese punctuation.
      -- Quotes use feedkeys with <Left> resolved so the cursor lands
      -- between the auto-paired quote characters.
      if char == "'" or char == '"' then
        local feed = vim.api.nvim_replace_termcodes(rhs, true, true, true)
        vim.api.nvim_feedkeys(feed, 'n', false)
      else
        vim.api.nvim_feedkeys(rhs, 'n', false)
      end
    end)
  end,
})

vim.api.nvim_create_user_command('BlinkImZhhToggle', function()
  M.toggle()
end, {})

return M

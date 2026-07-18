--- blink-im-zhh: a blink.cmp source for Chinese input via the 虎码 (HuCode)
--- shape-based code table.
---
--- This is a rewrite of `yehuohan/cmp-im` (specifically the `cmp_im_zhh` fork)
--- for blink.cmp instead of nvim-cmp.
---
--- Module-level state (`M.config`) is shared by reference with the source
--- instance, so `toggle()`/`setup()`/`toggle_chinese_symbol()` mutate it in
--- place and the running source observes the changes immediately.

local source_mod = require('blink-im-zhh.source')
local table_utils = require('blink-im-zhh.table')

local M = {}

--- Shared, module-level configuration. A single table reference is handed to
--- every source instance so that toggles are reflected live.
M.config = {
  enable = false,
  noice = true,
  maxn = 8,
  tables = nil,
  format = nil,
  chinese_symbol = false,
}

--- Name of this provider as reported by blink (used to detect IM candidates).
M.source_name = 'IM'

--- Merge user options into the shared config, in place.
---@param opts? table
function M.setup(opts)
  opts = opts or {}
  for k, v in pairs(opts) do
    M.config[k] = v
  end
end

--- Entry point called by blink.cmp: `require('blink-im-zhh').new(opts, config)`.
--- `opts` comes from `sources.providers.<id>.opts`; `config` is the full
--- provider table (kept for the source name). Both are merged into the shared
--- module config in place before constructing the source instance.
---@param opts? table
---@param config? table
---@return table
function M.new(opts, config)
  opts = opts or {}
  vim.tbl_deep_extend('force', M.config, opts)
  if config and config.name then
    M.source_name = config.name
  end
  return source_mod.new(M.config)
end

--- Enable/Disable the input method. Turning it off also dismisses the
--- Chinese-symbol keymaps. Returns the new enable state.
---@return boolean
function M.toggle()
  if M.config.noice then
    pcall(require('noice').cmd, 'dismiss')
  end
  M.config.enable = not M.config.enable
  if M.config.chinese_symbol then
    M.config.chinese_symbol = false
    for lhs, _ in pairs(table_utils.chinese_symbol()) do
      vim.keymap.del('i', lhs)
    end
    vim.notify('中文符号退出')
  end
  return M.config.enable
end

--- Toggle the Chinese punctuation feature. Requires the input method to be on.
--- When enabled, punctuation keys are remapped to their full-width variants
--- (quotes auto-pair). Returns the new Chinese-symbol state.
---@return boolean?
function M.toggle_chinese_symbol()
  if M.config.noice then
    pcall(require('noice').cmd, 'dismiss')
  end
  if not M.config.enable then
    vim.notify('请先启动输入法', vim.log.levels.ERROR)
    return
  end
  M.config.chinese_symbol = not M.config.chinese_symbol
  if M.config.chinese_symbol then
    for lhs, rhs in pairs(table_utils.chinese_symbol()) do
      vim.keymap.set('i', lhs, function()
        if require('blink.cmp').is_visible() then
          require('blink.cmp').accept()
        end
        vim.api.nvim_input(rhs)
      end)
    end
    vim.notify('中文符号启动')
  else
    for lhs, _ in pairs(table_utils.chinese_symbol()) do
      vim.keymap.del('i', lhs)
    end
    vim.notify('中文符号退出')
  end
  return M.config.chinese_symbol
end

--- Current enable state of the input method.
---@return boolean
function M.getStatus()
  return M.config.enable
end

--- Current state of the Chinese punctuation feature.
---@return boolean
function M.getChineseSymbolStatus()
  return M.config.chinese_symbol
end

--- Keymap handler factory for `<Space>`: commit the current IM candidate.
--- When the input method is enabled and the menu is visible with an IM item
--- selected, accept it; otherwise fall back (insert a normal space).
---@return fun(fallback: fun())
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

--- Keymap handler factory for `<CR>`: keep the typed code, do not commit.
--- When the input method is enabled and the menu is visible, cancel the
--- completion (preserving the typed code, closing the menu, not inserting a
--- newline). Otherwise fall back to the default `<CR>` behavior.
---@return fun(fallback: fun())
function M.confirmEnter()
  return function(fallback)
    if M.getStatus() and require('blink.cmp').is_visible() then
      require('blink.cmp').cancel()
      return
    end
    return fallback()
  end
end

--- Convenience user command to toggle the input method.
vim.api.nvim_create_user_command('BlinkImZhhToggle', function()
  M.toggle()
end, {})

return M

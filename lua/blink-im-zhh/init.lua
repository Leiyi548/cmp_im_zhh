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

--- Guard so `M.new` only seeds the shared config from `opts` ONCE. blink.cmp
--- instantiates the source lazily (and may rebuild it on reload / filetype
--- change), so re-applying `opts.enable = false` on every call would clobber a
--- live `toggle()`.
M._init = false

--- Set to true the first time the user calls `toggle()`, so that a provider's
--- `opts.enable` default can never reset a live toggle.
M._enable_overridden = false

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
--- provider table (kept for the source name).
---
--- `opts` seeds the shared module config ONLY ONCE (on the first call). This is
--- important because blink.cmp instantiates the source lazily and may (on
--- reload / per-filetype rebuild) call `new` again; re-applying
--- `opts.enable = false` on every call would clobber a live `toggle()`. Once
--- initialized, the running `M.config` (mutated by `toggle()`/`setup()`) is
--- handed to the source instance by reference, so toggles are observed live.
---@param opts? table
---@param config? table
---@return table
function M.new(opts, config)
  opts = opts or {}
  if not M._init then
    -- Seed defaults from opts on first call only. If the user already toggled
    -- the input method, do not let `opts.enable` reset it to the provider
    -- default.
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

--- Enable/Disable the input method. Turning it off also dismisses the
--- Chinese-symbol keymaps. Returns the new enable state.
---@return boolean
function M.toggle()
  if M.config.noice then
    -- Safe: `require` is evaluated INSIDE the pcall, so a missing `noice`
    -- module no longer crashes `toggle()` before the enable flag is flipped.
    -- The `cmd` call is also wrapped so a half-initialized noice cannot abort
    -- the toggle either.
    local ok, noice = pcall(require, 'noice')
    if ok and noice and noice.cmd then
      pcall(noice.cmd, 'dismiss')
    end
  end
  M.config.enable = not M.config.enable
  M._enable_overridden = true
  vim.notify('IM: ' .. (M.config.enable and 'on' or 'off'))
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
    local ok, noice = pcall(require, 'noice')
    if ok and noice and noice.cmd then
      pcall(noice.cmd, 'dismiss')
    end
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

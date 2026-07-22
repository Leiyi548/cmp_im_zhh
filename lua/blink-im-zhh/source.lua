--- blink.cmp source implementation for blink-im-zhh.
---
--- The source turns the code the user is typing (lowercase letters, optionally
--- preceded by a `;` prefix) into Chinese candidates using the 虎码 (HuCode)
--- shape-based table. Prefix matching is strict: every code in the table that
--- starts with the typed key yields one candidate per character.

local source = {}

local table_utils = require("blink-im-zhh.table")
local types = require("blink.cmp.types")

--- Construct a new source instance.
--- `opts` is the shared module-level config table (kept by reference so that
--- `toggle()`/`setup()` modifications are observed live).
---@param opts table
---@return table
function source.new(opts)
  local self = setmetatable({}, { __index = source })
  self.config = opts
  self.tbls = nil -- lazy-loaded list of loaded IM tables
  return self
end

--- Whether this source should participate in completion.
--- Only called by blink when not in a fast event; safe to just read a field.
---@return boolean
function source:enabled()
  return self.config.enable
end

--- Characters that should trigger the source.
---
--- blink.cmp only requests this source when the *newly-typed* character
--- belongs to this set (see `completion/init.lua` and
--- `completion/trigger/init.lua`). Custom Lua sources do NOT auto-trigger on
--- keyword/letter input, so 虎码 (HuCode) — a pure-lowercase-letter code —
--- must declare every letter explicitly. Without this, typing `a` (or `aa`)
--- would never call `get_completions`, yielding no Chinese candidates. We
--- also keep `;` as the explicit prefix trigger.
---@return string[]
function source:get_trigger_characters()
  local chars = {}
  for c in ("abcdefghijklmnopqrstuvwxyz"):gmatch(".") do
    chars[#chars + 1] = c
  end
  chars[#chars + 1] = ";"
  return chars
end

--- Lazily load every configured IM table (or the bundled 虎码 table) once.
function source:load_tbls()
  if not self.tbls then
    self.tbls = {}
    local files = self.config.tables or table_utils.load_zhh_table()
    for _, fn in ipairs(files) do
      local tbl = table_utils.load_tbl(fn)
      if tbl:valid() then
        self.tbls[#self.tbls + 1] = tbl
      else
        vim.notify(string.format("Failed to load %s as blink-im-zhh table", fn), vim.log.levels.WARN)
      end
    end
  end
end

--- Build a single CompletionItem for one candidate character.
---@param char string the Chinese character to insert
---@param key string the typed code (used for filter/sort)
---@param row integer 0-indexed cursor row
---@param start_char integer 0-indexed replace range start
---@param end_char integer 0-indexed replace range end (exclusive)
---@return table
function source:make_item(char, key, pre, row, start_char, end_char)
  -- 默认显示 "汉字 编码" 格式（如 "来 a"），可通过 format 自定义
  local label = char .. " " .. key
  if type(self.config.format) == "function" then
    label = self.config.format(key, char) or (char .. " " .. key)
  end

  return {
    label = label,
    kind = types.CompletionItemKind.Text,
    -- blink 模糊匹配用整行前缀（pre）作 keyword，filterText 必须以 pre 开头才匹配，
    -- 否则"中文后接编码"场景候选会被过滤掉。对齐 yehuohan/blink-cmp-im。
    filterText = pre .. key,
    -- Keep candidates grouped by code (stable ordering across tables).
    sortText = key,
    textEdit = {
      newText = char,
      range = {
        start = { line = row, character = start_char },
        ["end"] = { line = row, character = end_char },
      },
    },
    insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
  }
end

--- Core completion callback.
---@param ctx blink.cmp.Context
---@param callback fun(response: { items: table, is_incomplete_forward: boolean, is_incomplete_backward: boolean })
function source:get_completions(ctx, callback)
  -- Quick bail-out when the input method is disabled.
  if not self.config.enable then
    return callback({ items = {}, is_incomplete_forward = true, is_incomplete_backward = true })
  end

  self:load_tbls()

  -- 用 blink 提供的 ctx.cursor（字节位置，和 ctx.line 一致），避免 ctx.pos 单位不可靠
  -- 和 nvim_win_get_cursor 的异步光标问题。对齐 yehuohan/blink-cmp-im 的实现。
  local pre = ctx.line:sub(1, ctx.cursor[2]) -- 光标前前缀（字节索引）
  local row = ctx.cursor[1] - 1 -- 0-indexed row
  local col = ctx.cursor[2] -- 字节 col

  -- 虎码：以"进入插入模式时记录的边界列"为起点，只把边界之后的小写字母串当作
  -- 编码。这样 fff 之后重新进入插入模式再打 f，会补全"一"(码 f) 而不是 ffff，
  -- 忽略进入 normal 模式前残留的字母。没有边界记录时退化为原行为。
  local boundary = self.config._insert_start and self.config._insert_start[vim.api.nvim_get_current_buf()]
  local search_pre = (boundary and boundary >= 0) and pre:sub(boundary + 1) or pre

  -- 在前缀末尾找小写字母 run 作为 key（比从 col 往前扫描更简洁可靠，对中文也正确）
  local key = search_pre:match("%l+$")
  if not key then
    return callback({ items = {}, is_incomplete_forward = true, is_incomplete_backward = true })
  end

  -- ; 前缀支持：字母 run 前若是 ;，把 ; 纳入替换范围
  local before_key = pre:sub(1, #pre - #key)
  local has_semicolon = before_key:sub(-1) == ";"
  local start_char = has_semicolon and (col - #key - 1) or (col - #key)

  local items = {}
  local maxn = self.config.maxn or 1

  for _, tbl in ipairs(self.tbls) do
    local cnt = 0
    if tbl:ordered() then
      -- Ordered table: binary search the start, then scan forward.
      -- `li` is the line offset (one per record); `cnt` only counts emitted
      -- characters for the `maxn` limit. Mixing them (idx + cnt) skipped or
      -- duplicated records once a record carried more than one character.
      local idx = tbl:index(key)
      if idx then
        local li = 0
        repeat
          local kvs = tbl.lst[idx + li]
          if (not kvs) or (kvs[1]:sub(1, #key) ~= key) then
            break
          end
          for j = 2, #kvs do
            local char = kvs[j]
            items[#items + 1] = self:make_item(char, key, pre, row, start_char, col)
            cnt = cnt + 1
            if cnt >= maxn then
              break
            end
          end
          li = li + 1
        until cnt >= maxn
      end
    else
      -- Unordered table: brute-force scan (still fine under luajit).
      for _, kv in ipairs(tbl.lst) do
        if kv[1]:sub(1, #key) == key then
          cnt = cnt + 1
          items[#items + 1] = self:make_item(kv[2], key, pre, row, start_char, col)
        end
        if cnt >= maxn then
          break
        end
      end
    end
  end

  -- is_incomplete_forward: each extra letter changes the candidate set, so
  -- blink must re-request. is_incomplete_backward: re-request when deleting.
  return callback({
    items = items,
    is_incomplete_forward = true,
    is_incomplete_backward = true,
  })
end

return source

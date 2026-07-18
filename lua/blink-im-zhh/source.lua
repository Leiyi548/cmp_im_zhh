--- blink.cmp source implementation for blink-im-zhh.
---
--- The source turns the code the user is typing (lowercase letters, optionally
--- preceded by a `;` prefix) into Chinese candidates using the 虎码 (HuCode)
--- shape-based table. Prefix matching is strict: every code in the table that
--- starts with the typed key yields one candidate per character.

local source = {}

local table_utils = require('blink-im-zhh.table')
local dictionary = require('blink-im-zhh.dictionary')
local types = require('blink.cmp.types')

--- Construct a new source instance.
--- `opts` is the shared module-level config table (kept by reference so that
--- `toggle()`/`setup()` modifications are observed live).
---@param opts table
---@return table
function source.new(opts)
  local self = setmetatable({}, { __index = source })
  self.config = opts
  self.tbls = nil -- lazy-loaded list of loaded IM tables
  self.dict = nil -- lazy-loaded reverse dictionary (char -> pinyin/radical)
  return self
end

--- Whether this source should participate in completion.
--- Only called by blink when not in a fast event; safe to just read a field.
---@return boolean
function source:enabled()
  return self.config.enable
end

--- Non-alphanumeric characters that should trigger the source.
--- Lowercase letters are keyword characters and are auto-triggered by blink,
--- so we only need to declare `;` as an explicit trigger prefix.
---@return string[]
function source:get_trigger_characters()
  return { ';' }
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
        vim.notify(string.format('Failed to load %s as blink-im-zhh table', fn), vim.log.levels.WARN)
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
function source:make_item(char, key, row, start_char, end_char)
  local label = char
  if type(self.config.format) == 'function' then
    label = self.config.format(key, char) or char
  end

  return {
    label = label,
    kind = types.CompletionItemKind.Text,
    -- Let blink fuzzy match the typed code against the candidate.
    filterText = key,
    -- Keep candidates grouped by code (stable ordering across tables).
    sortText = key,
    textEdit = {
      newText = char,
      range = {
        start = { line = row, character = start_char },
        ['end'] = { line = row, character = end_char },
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

  local line = ctx.line
  local col = ctx.pos.col -- 0-indexed: char just before cursor is line:sub(col, col)

  -- Scan backwards collecting the run of lowercase letters before the cursor.
  local i = col
  while i > 0 and line:sub(i, i):match('%l') do
    i = i - 1
  end

  -- If the run is immediately preceded by ';', include it in the replace range.
  local has_semicolon = (i > 0 and line:sub(i, i) == ';')
  local start_char = has_semicolon and (i - 1) or i -- 0-indexed range start
  local key = line:sub(i + 1, col)

  if key == '' then
    return callback({ items = {}, is_incomplete_forward = true, is_incomplete_backward = true })
  end

  local row = ctx.pos.row
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
          if (not kvs) or (not kvs[1]:match('^' .. key)) then
            break
          end
          for j = 2, #kvs do
            local char = kvs[j]
            items[#items + 1] = self:make_item(char, key, row, start_char, col)
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
        if kv[1]:match('^' .. key) then
          cnt = cnt + 1
          items[#items + 1] = self:make_item(kv[2], key, row, start_char, col)
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

--- Lazily resolve documentation (pinyin / radical) only when needed, so the
--- menu itself never pays the cost of loading the 2.3MB reverse dictionary.
---@param item table
---@param callback fun(item: table)
function source:resolve(item, callback)
  if not self.dict then
    self.dict = dictionary.load_zhh_dictionary()
  end
  -- Index by the inserted character (always present in textEdit.newText),
  -- which is robust even when `format` rewrites the label.
  local char = item.textEdit and item.textEdit.newText or item.label
  item.documentation = {
    kind = 'markdown',
    value = self.dict[char] or '',
  }
  return callback(item)
end

return source

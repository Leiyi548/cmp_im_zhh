--- Table loading and matching utilities for blink-im-zhh.
---
--- Ported from the original `cmp_im` plugin (utils.lua). The IM table is a plain
--- text file where each line is `code char1 char2 ...` separated by whitespace.
--- The table is loaded once and stored as a list `lst` (each element is a list
--- whose first element is the code and the rest are the candidate characters).
--- When the table is sorted in ascending order of the code, an inverted index
--- `inv` is kept so that prefix matching can start from a binary search.

local M = {}

--- Metatable carried by every loaded table object.
local T = {}

--- Whether the table was loaded with at least one valid entry.
function T.valid(self)
  return #self.lst > 0
end

--- Whether the table is sorted in ascending order (so binary search is usable).
--- Returns the inverted index `inv` (nil when the table is not ordered).
function T.ordered(self)
  return self.inv
end

--- Binary search the sorted `lst` for the first entry whose code has `key` as a
--- prefix. Returns the (1-indexed) list index, or nil when nothing matches.
---@param lst table[] list of { code, char, ... }
---@param key string
---@return integer?
local function search(lst, key)
  local lo = 1
  local hi = #lst
  while lo < hi do
    local mi = math.floor((lo + hi) / 2)
    if vim.stricmp(key, lst[mi][1]) > 0 then
      lo = mi + 1 -- Make sure lst[lo] >= key
    else
      hi = mi
    end
  end
  local idx = lo
  if lst[idx][1]:sub(1, #key) == key then
    return idx
  end
  return nil
end

--- Search the IM-key inside the loaded table list.
--- Returns the list index of the first entry whose code starts with `key`.
---@param key string
---@return integer?
function T.index(self, key)
  local idx = self.inv and self.inv[key]
  if not idx then
    idx = search(self.lst, key)
  end
  return idx
end

--- Split a line into tokens on non-whitespace runs (default).
---@param line string
---@param sep? string
---@return string[]
local function split(line, sep)
  if not sep then
    sep = "%S+"
  end
  local list = {}
  for ele in string.gmatch(line, sep) do
    list[#list + 1] = ele
  end
  return list
end

--- Locate the bundled `tables/zhh.txt` relative to this plugin's init.lua.
--- Returns an array with a single table path (the default 虎码 / HuCode table).
---@return string[]
function M.load_zhh_table()
  local dir = vim.fs.dirname(vim.api.nvim_get_runtime_file("lua/blink-im-zhh/init.lua", false)[1])
  dir = vim.fs.dirname(vim.fs.dirname(dir)) -- plugin root
  local tbls = {}
  tbls[#tbls + 1] = string.format("%s/tables/%s.txt", dir, "zhh")
  return tbls
end

--- Left-hand-side -> right-hand-side mapping for the Chinese punctuation feature.
--- The `'` and `"` entries emit an auto-paired form with `<Left>` to move the
--- cursor between the quotes.
---@return table<string, string>
function M.chinese_symbol()
  return {
    ["!"] = "！",
    ["("] = "（",
    [")"] = "）",
    ["["] = "【",
    ["]"] = "】",
    [":"] = "：",
    ["'"] = "‘’<Left>", -- As auto pair
    ['"'] = "“”<Left>", -- As auto pair
    [","] = "，",
    ["."] = "。",
    ["<"] = "《",
    [">"] = "》",
    ["?"] = "？",
  }
end

--- Load an IM table from a text file.
---
--- Each line is split into a list `{ code, char1, char2, ... }`. A reverse index
--- `inv` maps each code to its first line number, and `inv` is set to nil when
--- the codes are not in ascending order (forcing a brute-force scan later).
---@param filename string
---@return table
function M.load_tbl(filename)
  local fp = io.open(filename, "r")
  local lst = {} -- IM key-values list with key=lst[1] and values = lst[2:]
  local inv = {} -- Inverted lst: code -> first line index
  local last = nil
  local order = true

  if fp then
    local line = fp:read()
    while line do
      local parts = split(line)
      if #parts >= 2 then
        lst[#lst + 1] = parts

        local key = parts[1]
        if not inv[key] then
          inv[key] = #lst
        end

        if order and last and vim.stricmp(last, key) > 0 then
          order = false
        end
        last = key
      end
      line = fp:read()
    end
    fp:close()
  end

  if not order then
    inv = nil
  end

  return setmetatable({ lst = lst, inv = inv }, { __index = T })
end

return M

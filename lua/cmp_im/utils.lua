local M = {}
local T = {}

function T.valid(self)
	return #self.lst > 0
end

function T.ordered(self)
	return self.inv
end

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
	if string.match(lst[idx][1], "^" .. key) then
		return idx
	end
	return nil
end

---Search the IM-key within IM table list
---Return lst index of IM-key that:
---     lst[index - 1].key < lst[index].key
--- and lst[index + 1].key >= lst[index].key
--- and lst[index + 1].key =~# '^' .. lst[index].key
function T.index(self, key)
	local idx = self.inv[key]
	if not idx then
		idx = search(self.lst, key)
	end
	return idx
end

---String split with space by default
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

-- 加载虎码的码表
function M.load_zhh_table()
	local dir = vim.fs.dirname(vim.api.nvim_get_runtime_file("lua/cmp_im/init.lua", false)[1])
	dir = vim.fs.dirname(vim.fs.dirname(dir))
	local tbls = {}
	tbls[#tbls + 1] = string.format("%s/tables/%s.txt", dir, "zhh")
	return tbls
end

function M.chinese_symbol()
	return {
		["`"] = "·",
		["!"] = "！",
		["$"] = "￥",
		["^"] = "……",
		["("] = "（",
		[")"] = "）",
		["["] = "【",
		["]"] = "】",
		["\\"] = "、",
		[":"] = "：",
		["'"] = "‘’<Left>", -- As auto pair
		['"'] = "“”<Left>", -- As auto pair
		[","] = "，",
		["."] = "。",
		["<"] = "《",
		[">"] = "》",
		["?"] = "？",
		["_"] = "——",
	}
end

---Load IM table
-- 这段Lua代码是一个函数，用于从文本文件中加载一个键值对表（key-values table）。让我解释一下它的工作原理：
--
-- M.load_tbl(filename) 函数接受一个文件名作为参数，该文件包含键值对数据。
-- 函数首先尝试打开指定的文件 (io.open(filename, 'r'))。
-- 如果成功打开文件，则创建了两个空表 lst 和 inv。lst 用于存储键值对列表，其中键为 lst[1]，其余为值。inv 用于存储键的反向索引，即键到位置的映射。
-- 然后，函数逐行读取文件内容，对每一行进行处理。
-- 如果某行包含至少两个部分（键和至少一个值），则将其分割，并将其添加到 lst 表中。然后，将该键添加到 inv 表中，如果该键之前没有出现过，则将其位置记录到 inv 表中。
-- 此外，函数检查键的顺序是否按字母顺序排列。如果不是，则将 inv 表设置为 nil。
-- 最后，函数返回一个包含 lst 和 inv 表的元表，其中 lst 表存储键值对列表，inv 表存储键的反向索引。
-- 整体来说，该函数的作用是读取一个包含键值对数据的文本文件，并以表的形式返回这些数据。
function M.load_tbl(filename)
	-- 打开文件
	local fp = io.open(filename, "r")
	local lst = {} -- IM key-values list with key=lst[1] and values = lst[2:]
	local inv = {} -- Inverted lst
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

				if order then
					if last and vim.stricmp(last, key) > 0 then
						order = false
					end
				end
				last = key
			end
			line = fp:read()
		end
	end
	if not order then
		inv = nil
	end

	return setmetatable({ lst = lst, inv = inv }, { __index = T })
end

return M

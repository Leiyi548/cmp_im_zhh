local cmp = require("cmp")
local utils = require("cmp_im.utils")
local dictionary = require("cmp_im.dictionary")
local source = {}
---Default options
local im_opts = {
	chinese_symbol = false,
	enable = false,
	tables = utils.load_zhh_table(),
	format = function(key, text)
		local dict = dictionary.load_zhh_dictionary()
		-- 如果是"我",那么 key 就是 t, text 就是我
		return vim.fn.printf("%-2S %s", text, dict[text])
	end,
	-- 能够显示有多少
	maxn = 1,
}

---All IM tables
local im_tbls = nil

-- 加载 table
local function load_tbls(files)
	-- 如果 opt 不启用，后面也就不加载码表
	if not im_opts.enable then
		return
	end
	if not im_tbls then
		im_tbls = {}
		for _, fn in ipairs(files) do
			local tbl = utils.load_tbl(fn)
			if tbl:valid() then
				im_tbls[#im_tbls + 1] = tbl
			else
				vim.notify(string.format("Failed to load %s as cmp-im's table", fn), vim.log.levels.WARN)
			end
		end
	end
end

local function cmp_item(key, val, params)
	local ctx = params.context
	local cur = ctx.cursor
	return {
		label = im_opts.format(key, val),
		sortText = key,
		filterText = key,
		textEdit = {
			newText = val,
			insert = {
				["start"] = { line = cur.line, character = cur.character - (cur.col - params.offset) },
				["end"] = { line = cur.line, character = cur.character },
			},
		},
	}
end

local function match_tbls(params)
	local res = {}
	if not im_tbls then
		return res
	end

	local key = string.sub(params.context.cursor_before_line, params.offset)
	for _, tbl in ipairs(im_tbls) do
		local cnt = 0
		if tbl:ordered() then
			-- Match start from idx
			local idx = tbl:index(key)
			if idx then
				repeat
					local kvs = tbl.lst[idx + cnt]
					if (not kvs) or (not string.match(kvs[1], "^" .. key)) then
						break
					end
					for i, v in ipairs(kvs) do
						if i >= 2 then
							res[#res + 1] = cmp_item(kvs[1], v, params)
							cnt = cnt + 1
							if cnt >= im_opts.maxn then
								break
							end
						end
					end
				until cnt >= im_opts.maxn
			end
		else
			-- A brute force match that still provides a pretty acceptable performance!(Yes, luajit)
			for _, kv in ipairs(tbl.lst) do
				if string.match(kv[1], "^" .. key) then
					cnt = cnt + 1
					res[#res + 1] = cmp_item(kv[1], kv[2], params)
				end
				if cnt >= im_opts.maxn then
					break
				end
			end
		end
	end

	return res
end

function source:is_available()
	return im_opts.enable
end

-- 综合起来，[[\l+]] 表示一个字符类，其中包含所有的字母字符和加号字符，即匹配任何一个字母字符或者加号字符。
function source:get_keyword_pattern()
	return [[;\?\l\+]]
end

-- 触发 cmp 的按键
function source:get_trigger_characters()
	return {
		"a",
		"b",
		"c",
		"d",
		"e",
		"f",
		"g",
		"h",
		"i",
		"j",
		"k",
		"l",
		"m",
		"n",
		"o",
		"p",
		"q",
		"r",
		"s",
		"t",
		"u",
		"v",
		"w",
		"x",
		"y",
		"z",
		";",
	}
end

-- 补全的关键函数
function source:complete(params, callback)
	load_tbls(im_opts.tables)
	-- local t0 = vim.fn.reltime()
	local res = match_tbls(params)
	-- vim.notify('Match elapsed: ' .. tostring(vim.fn.reltimestr(vim.fn.reltime(t0))))
	if #res > 0 then
		return callback(res)
	end
	return callback()
end

---Setup IM's options
local function setup(opts)
	im_opts = vim.tbl_deep_extend("keep", opts, im_opts)
end

---Enable/Disable IM source
local function toggle()
	im_opts.enable = not im_opts.enable
	-- 如果中文符号启动的话，就关闭它
	if im_opts.chinese_symbol then
		im_opts.chinese_symbol = false
		vim.notify("中文符号退出")
	end
	return im_opts.enable
end

local function toggle_chinese_symbol()
	if not im_opts.enable then
		vim.notify("请先启动虎码")
		return
	end
	im_opts.chinese_symbol = not im_opts.chinese_symbol
	-- set chinese_symbol keymap
	if im_opts.chinese_symbol then
		for lhs, rhs in pairs(utils.chinese_symbol()) do
			vim.keymap.set("i", lhs, rhs)
		end
		vim.notify("中文符号启动")
	else
		for lhs, rhs in pairs(utils.chinese_symbol()) do
			vim.keymap.del("i", lhs)
		end
		vim.notify("中文符号退出")
	end
	-- remove chinese_symbol keymap
	return im_opts.chinese_symbol
end

local function getStatus()
	return im_opts.enable
end

local function getChineseSymbolStatus()
	return im_opts.chinese_symbol
end

---Select the entry from IM
local function select(index)
	return function(fallback)
		if im_opts.enable and cmp.visible() then
			local entries = cmp.get_entries()
			if index and index > 0 then
				local num = 0
				for k, e in ipairs(entries) do
					if e.source.name == "IM" then
						num = num + 1
						if num >= index then
							-- `count` works only after `select_next_item()` is called once at least
							cmp.select_next_item()
							cmp.select_next_item({ count = k - 1 })
							return cmp.confirm()
						end
					end
				end
			end
			if #entries > 0 and entries[1].source.name == "IM" then
				return cmp.confirm({ select = true })
			end
		end
		return fallback()
	end
end

return {
	source = source,
	setup = setup,
	toggle = toggle,
	toggle_chinese_symbol = toggle_chinese_symbol,
	getChineseSymbolStatus = getChineseSymbolStatus,
	getStatus = getStatus,
	select = select,
}

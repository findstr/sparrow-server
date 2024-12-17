local libworld = require "lib.world"

local function set_to_desc(set)
	local t = {}
	for k, _ in pairs(set) do
		t[#t+1] = k
	end
	table.sort(t, function(a, b) return a > b end)
	return t
end

local function cmp_array(a, b)
	if #a ~= #b then
		print(string.format("FAIL cmp_array:{%s}:{%s}",
			table.concat(a, ","),
			table.concat(b, ",")))
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			print(string.format("FAIL %d cmp_array:{%s}:{%s}",
				i,
				table.concat(a, ","),
				table.concat(b, ",")))
			return false
		end
	end
	return true
end

local function test_new_and_free()
	local entities = {}
	local fighting = {}
	local world = libworld.new(0, entities, fighting)
	-- 先创建10个实体
	for i = 0, 9 do
		local eid = world:enter(i, 0, 0, 0, 0)
		assert(eid == i)    --eid应该是顺序创建的
		assert(entities[i]) --对应的table已经创建成功了
	end
	-- 删除第 3, 5, 7 个实体（释放回 free 链表）
	for _, eid in ipairs({3, 5, 7}) do
		world:dead(eid)
	end
	world:tick(0) -- 释放实体
	local alive = {}
	local free = {}
	world:dump(alive, free) -- 打印实体信息
	assert(cmp_array(alive, {9, 8, 6, 4, 2, 1, 0}))
	local xfree = {3, 5, 7}
	for i = 10, 127 do
		xfree[#xfree+1] = i
	end
	assert(cmp_array(free, xfree))
	for _, eid in ipairs({3, 5, 7}) do
		assert(not entities[eid]) --对应的table已经被释放了
	end
	-- 再创建 3 个实体，eid应该是3, 5, 7
	for i, xeid in ipairs({3, 5, 7}) do
		local eid = world:enter(i, 0, 0, 0, 0)
		assert(eid == xeid)
	end
end

local function test_expand()
	local entities = {}
	local fighting = {}
	local set = {}
	local world = libworld.new(0, entities, fighting)
	-- 创建128个实体
	for i = 0, 127 do
		local eid = world:enter(i, 0, 0, 0, 0)
		assert(eid == i)
		set[eid] = true
	end
	local alive = {}
	local free = {}
	local cap = world:dump(alive, free) -- 打印实体信息
	assert(cap == 128)
	-- 再创建10个实体，从128之后就会触发扩容
	for i = 1, 10 do
		local eid = world:enter(i, 0, 0, 0, 0)
		assert(eid == 127+i)
		set[eid] = true
	end
	-- 删除第 128+3, 128+5, 128+7 个实体（释放回 free 链表）
	for _, eid in ipairs({128+3, 128+5, 128+7}) do
		world:dead(eid)
		set[eid] = nil
	end
	world:tick(0) -- 释放实体
	alive = {}
	free = {}
	cap = world:dump(alive, free) -- 打印实体信息
	assert(cap == 256)
	assert(cmp_array(alive, set_to_desc(set)))
	local xfree = {128+3, 128+5, 128+7}
	for i = 128+10, 255 do
		xfree[#xfree+1] = i
	end
	assert(cmp_array(free, xfree))

	-- 全部释放
	for i = 0, 128+10-1 do
		world:dead(i)
	end
	world:tick(0) -- 释放实体
	local oalive = alive
	alive = {}
	free = {}
	cap = world:dump(alive, free) -- 打印实体信息
	assert(cap == 256)
	assert(cmp_array(alive, {}))
	local ofree = {}
	for i = 0, 255 do
		assert(not entities[i])
		ofree[#ofree+1] = i
	end
	table.sort(free, function(a, b) return a < b end)
	assert(cmp_array(free, ofree))
end

local function test_life()
	local entities = {}
	local fighting = {}
	local world = libworld.new(0, entities, fighting)
	-- 创建10个实体
	for i = 0, 10 do
		local eid = world:enter(i, 0, 0, 0, 0)
		assert(eid == i)
	end
	-- 假设时间过了60秒
	world:tick(60*1000)
	-- 所有实体都老死了
	assert(next(fighting) == nil)
	assert(next(entities) == nil)
	local alive = {}
	local free = {}
	local cap = world:dump(alive, free) -- 打印实体信息
	assert(cap == 128)
	--此时没有存活的小兵
	assert(#alive == 0)
	--所有小兵均已经释放
	assert(#free == cap)
end

local function test_match()
	local entities = {}
	local fighting = {}
	local xx = 0.5
	local zz = 0.5
	local world = libworld.new(0, entities, fighting)
	local eid1 = world:enter(1000, 0, 0, 0, 0)
	local eid2 = world:enter(1000, 0, xx, zz, 0)
	local eid3 = world:enter(1001, 0, xx, zz, 0)

	-- 没有tick之前，所有实体保持静默
	local e1 = entities[eid1]
	assert(e1.uid == 1000)
	assert(e1.lid == 0)
	assert(e1.x == 0)
	assert(e1.z == 0)
	assert(not e1.target)
	local e2 = entities[eid2]
	assert(e2.uid == 1000)
	assert(e2.lid == 0)
	assert(e2.x == xx)
	assert(e2.z == zz)
	assert(not e2.target)
	local e3 = entities[eid3]
	assert(e3.uid == 1001)
	assert(e3.lid == 0)
	assert(e3.x == xx)
	assert(e3.z == zz)
	assert(not e3.target)

	-- tick之后，实体开始匹配, 但是并不会移动
	world:tick(100)
	assert(e1.x == 0)
	assert(e1.z == 0)
	assert(e1.target == eid3)
	assert(e1.action == 1)
	assert(e2.x == xx)
	assert(e2.z == zz)
	assert(e2.target == eid3)
	assert(e2.action == 2)
	assert(e3.x == xx)
	assert(e3.z == zz)
	assert(e3.target == eid2)
	assert(e3.action == 2)
	assert(fighting[eid2])
	assert(fighting[eid3])

	-- 再次tick，实体开始移动
	world:tick(1000)
	assert(e1.x > 0.0 and e1.x < xx)
	assert(e1.z > 0.0 and e1.z < zz)
	assert(e1.target == eid3)

	--e2和e3互为目标，所以他们的位置应该是相同的
	assert(e2.x == xx)
	assert(e2.z == zz)
	assert(e2.target == eid3)
	assert(e3.x == xx)
	assert(e3.z == zz)
	assert(e3.target == eid2)
end

test_new_and_free()
test_expand()
test_life()
test_match()

print("test `world` success")
local M = {}
local pairs = pairs

local length = 0
local seq = {}
local map = {}

local marshal = function(v, schema)
	return v.hello .. ":" .. v.world
end

local function overwrite(v, t)
	local i = length + 1
	local k = map[v]
	if k then
		seq[k] = nil
	end
	length = i
	map[v] = length
	seq[length] = t
end

function M.hset(dbk, k, v, schema)
	local t = {"hset", dbk, k, v, schema}
	overwrite(v, t)
end

function M.hdel(dbk, k)
	length = length + 1
	seq[length] = {"hdel", dbk, k}
end

function M.set(dbk, v, schema)
	local t = {"set", dbk, v, schema}
	overwrite(v, t)
end

function M.del(dbk)
	length = length + 1
	seq[length] = {"del", dbk}
end

function M.flush()
	if length == 0 then
		return
	end
	for k, _ in pairs(map) do
		map[k] = nil
	end
	local j = 0
	local pipeline = seq
	for i = 1, length do
		local cmd
		cmd = seq[i]
		if cmd then
			local op = cmd[1]
			if op == "set" or op == "hset" then
				local n = #cmd
				local dat = marshal(cmd[n-1], cmd[n])
				cmd[n] = nil
				cmd[n-1] = dat
			end
			j = j + 1
			seq[j] = cmd
		end
	end
	for i = j+1, length do
		seq[i] = nil
	end
	length = 0
	seq = {}
	return pipeline
end

return M
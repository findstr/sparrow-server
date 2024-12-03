local json = require "core.json"
local cluster = require "lib.cluster"
local node = require "lib.conf.node"
local router = require "app.router.cluster"

local kick_users
local uid_to_id = {}
local fd_uid_set = setmetatable({}, {__index = function(t, k)
	local v = {}
	t[k] = v
	return v
end})


router.kick_r = function(body, fd)
	--TODO:
	return {}
end


local function establish(name, id, fd)
	--TODO: handshake
end

local M = {}
local cap
function M.start(kick)
	cluster.watch_establish(establish)
	cluster.connect("role")
	cap = cluster.capacity["role"]
end

function M.assign(uid)
	local id = node.id("role", uid % cap + 1)
	fd_uid_set[id][uid] = true
	uid_to_id[uid] = id
	return id
end

local ack_cmd = setmetatable({}, {__index = function(t, k)
	local v = k:gsub("_r$", "_a")
	print("****ack", k, v)
	t[k] = v
	return v
end})

function M.forward(uid, cmd, body)
	local id = uid_to_id[uid]
	print("-----------forward req", uid, cmd, id)
	if not id then
		return nil
	end
	local ack = cluster.call(id, "forward_r", {
		uid = uid,
		cmd = cmd,
		body = json.encode(body),
	})
	print("-----------forward ack", ack)
	if not ack then
		return nil
	end
	local body
	if ack.body then
		body = json.decode(ack.body)
	else
		body = {}
	end
	return ack_cmd[cmd], body
end

return M

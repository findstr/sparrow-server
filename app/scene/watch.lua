local logger = require "core.logger"
local cluster = require "lib.cluster"
local clusterp = require "app.proto.cluster"

local M = {}
local pairs = pairs
local uid_to_node = {}
local node_uid_set = setmetatable({}, {
	__index = function(t, k)
		local v = {}
		t[k] = v
		return v
	end
})

function M.online(uid, nodeid)
	uid_to_node[uid] = nodeid
	node_uid_set[nodeid][uid] = true
end

function M.offline(uid)
	local nodeid = uid_to_node[uid]
	if not nodeid then
		logger.error("[scene] offline uid:", uid, "has no online")
		return
	end
	node_uid_set[nodeid][uid] = nil
end

function M.broadcast(cmd, obj)
	local body = clusterp:encode(cmd, obj)
	for nodeid, uid_set in pairs(node_uid_set) do
		local uidlist = {}
		for uid in pairs(uid_set) do
			uidlist[#uidlist + 1] = uid
		end
		cluster.send(nodeid, "multicast_n", {
			uids = uidlist,
			cmd = cmd,
			body = body,
		})
	end
end

return M

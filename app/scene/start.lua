local logger = require "core.logger"
local args = require "lib.args"
local cluster = require "lib.cluster"
local router = require "lib.router.cluster"
local clusterp = require "app.proto.cluster"
local role = cluster.services.role
local pairs = pairs

local uid_to_sid = {}
local uid_to_fd = {}
local server_online = setmetatable({}, {
	__index = function(t, k)
		local v = {
			aoi_world = nil,
		}
		t[k] = v
		return v
	end
})

local function multicast(uid_set, cmd, obj)
	local fd_uid_list = setmetatable({}, {
		__index = function(t, k)
			local v = {}
			t[k] = v
			return v
		end
	})
	for uid in pairs(uid_set) do
		local fd = uid_to_fd[uid]
		if fd then
			local uid_list = fd_uid_list[fd]
			uid_list[#uid_list + 1] = uid
		end
	end
	local body = clusterp:encode(cmd, obj)
	for fd, uid_list in pairs(fd_uid_list) do
		role:call(fd, "multicast_n", {
			uids = uid_list,
			cmd = cmd,
			body = body,
		})
	end
end

function router.scene_enter_r(req, fd)
	local uid = req.uid
	local sid = req.sid
	uid_to_sid[uid] = sid
	uid_to_fd[uid] = fd
	server_online[sid][uid] = true
	return {
		players = {}
	}
end

function router.scene_leave_r(req, _)
	local uid = req.uid
	local sid = uid_to_sid[uid]
	uid_to_sid[uid] = nil
	uid_to_fd[uid] = nil
	server_online[sid][uid] = nil
end

function router.scene_move_r(req, _)
	local uid = req.uid
	local sid = uid_to_sid[uid]
	if not sid then
		return
	end
	local players = server_online[sid]
	multicast(players, "scene_move_n", req)
end

cluster.watch_establish(function (name, id, fd)
	logger.info("[scene] establish:", name, "id:", id, "fd:", fd)
end)

cluster.listen(args.listen)
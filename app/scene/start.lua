local logger = require "core.logger"
local cluster = require "core.cluster"
local cleanup = require "lib.cleanup"
local callret = require "app.proto.callret"
local router = require "lib.router.cluster"
local clusterp = require "app.proto.cluster"
local args = require "lib.args"
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
		service.multicast_n(fd, {
			uids = uid_list,
			cmd = cmd,
			body = body,
		})
	end
end

function router.hello_r(req)
	logger.info("[scene] hello_r", req.name, req.id)
	assert(req.name == "role", req.name)
	return {}
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

local function unmarshal(cmd, buf, sz)
	return clusterp:decode(cmd, buf, sz)
end

local function marshal(cmd, body)
	cmd = clusterp:tag(cmd)
	print("marshal", cmd, body)
	return cmd, clusterp:encode(cmd, body)
end

service = cluster.new {
	callret = callret(clusterp),
	marshal = marshal,
	unmarshal = unmarshal,
	call = function(body, cmd, fd)
		print("[scene] call", cmd, body)
		return router[cmd](body, fd)
	end,
	close = function(fd, errno)
		logger.info("[scene] close", fd, errno)
	end,
}

local ok, err = service.listen(args.listen)
if not ok then
	logger.error("[scene] listen addr:", args.listen, "error:", err)
	return cleanup()
end

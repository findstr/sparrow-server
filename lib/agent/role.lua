local core = require "core"
local json = require "core.json"
local cleanup = require "lib.cleanup"
local args = require "lib.args"
local logger = require "core.logger"
local cluster = require "core.cluster"
local conf = require "lib.conf.service"
local router = require "lib.router.cluster"
local callret = require "app.proto.callret"
local clusterp = require "app.proto.cluster"
local ipairs = ipairs
local pairs = pairs

local kick_users
local function unmarshal(cmd, buf, size)
	return clusterp:decode(cmd, buf, size)
end

local function marshal(cmd, body)
	cmd = clusterp:tag(cmd)
	return cmd, clusterp:encode(cmd, body, true)
end

local fd_to_id = {}
local id_to_fd = {}
local id_to_addr = {}
local uid_to_fd = {}
local fd_uid_set = setmetatable({}, {__index = function(t, k)
	local v = {}
	t[k] = v
	return v
end})

local role

router.kick_r = function(body, fd)
	--TODO:
	return {}
end

local function event_addr(id, addr)
	id_to_addr[id] = addr
	logger.debug("[role] event addr id:", id, "addr:", addr)
	if addr then
		local fd = role.connect(addr)
		if not fd then
			logger.error("[role] connect to", addr, "error")
			return
		end
		local ack = role.hello_r(fd, {
			id = id,
			name = args.service,
		})
		if ack then
			fd_to_id[fd] = id
			id_to_fd[id] = fd
			logger.info("[role] connect to id:", id, "addr:", addr, "success")
		else
			core.fork(function()
				logger.error("[role] connect to id:", id, "addr:", addr, "fail, retry")
				event_addr(id, addr)
			end)
		end
	else
		role.close(addr)
		local fd = id_to_fd[id]
		if fd then
			fd_to_id[fd] = nil
			id_to_fd[id] = nil
		end
	end
end

role = cluster.new {
	callret = callret(clusterp),
	marshal = marshal,
	unmarshal = unmarshal,
	call = function(body, cmd, fd)
		return router[cmd](body, fd)
	end,
	close = function(fd, errno)
		local id = fd_to_id[fd]
		logger.debug("close", id, fd, errno)
		if not id then
			return
		end
		fd_to_id[fd] = nil
		id_to_fd[id] = nil
		local uid_set = fd_uid_set[fd]
		fd_uid_set[fd] = nil
		for uid in pairs(uid_set) do
			uid_to_fd[uid] = nil
		end
		kick_users(uid_set)
		local addr = id_to_addr[id]
		logger.error("[role] close id:", id, "addr:", addr, "fd:", fd, "errno:", errno)
		core.fork(function()
			event_addr(id, addr)
		end)
	end,
}

local M = {}
local cap
function M.start(kick)
	local desc = conf.get("role")
	if not desc then
		logger.error("[role] get conf error")
		return cleanup()
	end
	cap = desc.capacity
	kick_users = kick
	conf.watch("role", event_addr)
	for id, addr in ipairs(desc) do
		event_addr(id, addr)
	end
end

function M.assign(uid)
	local id = uid % cap + 1
	local fd = id_to_fd[id]
	if fd then
		fd_uid_set[fd][uid] = true
		uid_to_fd[uid] = fd
	end
	return fd
end

local ack_cmd = setmetatable({}, {__index = function(t, k)
	local v = k:gsub("_r$", "_a")
	print("****ack", k, v)
	t[k] = v
	return v
end})

function M.forward(uid, cmd, body)
	local fd = uid_to_fd[uid]
	print("-----------forward req", uid, cmd, fd)
	if not fd then
		return nil
	end
	local ack = role.forward_r(fd, {
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

function M.rpc()
	return role
end

return M

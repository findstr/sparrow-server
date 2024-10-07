local core = require "core"
local cleanup = require "lib.cleanup"
local args = require "lib.args"
local logger = require "core.logger"
local cluster = require "core.cluster"
local conf = require "lib.conf.service"
local router = require "lib.router.cluster"
local callret = require "app.proto.callret"
local clusterp = require "app.proto.cluster"
local ipairs = ipairs

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

local scene

local function event_addr(id, addr)
	id_to_addr[id] = addr
	logger.debug("[role] event addr id:", id, "addr:", addr)
	if addr then
		local fd = scene.connect(addr)
		if not fd then
			logger.error("[role] connect to", addr, "error")
			return
		end
		local ack = scene.hello_r(fd, {
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
		scene.close(addr)
		local fd = id_to_fd[id]
		if fd then
			fd_to_id[fd] = nil
			id_to_fd[id] = nil
		end
	end
end

scene = cluster.new {
	callret = callret(clusterp),
	marshal = marshal,
	unmarshal = unmarshal,
	call = function(body, cmd, fd)
		return router[cmd](body, fd)
	end,
	close = function(fd, errno)
		local id = fd_to_id[fd]
		if not id then
			return
		end
		fd_to_id[fd] = nil
		id_to_fd[id] = nil
		local addr = id_to_addr[id]
		logger.error("[role] close id:", id, "addr:", addr, "fd:", fd, "errno:", errno)
		core.fork(function()
			event_addr(id, addr)
		end)
	end,
}

local M = {}
function M.start()
	local desc = conf.get("scene")
	if not desc then
		logger.error("[role] get conf error")
		return cleanup()
	end
	conf.watch("scene", event_addr)
	for id, addr in ipairs(desc) do
		event_addr(id, addr)
	end
end

function M.rpc()
	return scene
end

function M.fd(id)
	return id_to_fd[id]
end

return M

local core = require "core"
local cleanup = require "lib.cleanup"
local serviceid = require "lib.serviceid"
local router = require "lib.router.cluster"
local args = require "lib.args"
local logger = require "core.logger"
local cluster = require "core.cluster"
local conf = require "lib.conf.service"
local callretp = require "app.proto.callret"
local clusterp = require "app.proto.cluster"
local ipairs = ipairs

local callret = callretp(clusterp)
local function nop(...) end
local function unmarshal(typ, cmd, buf, size)
	if typ == "response" then
		cmd = callret[cmd]
	end
	return clusterp:decode(cmd, buf, size)
end

local function marshal(typ, cmd, body)
	if typ == "response" then
		if not body then
			return nil, nil
		end
		cmd = callret[cmd]
		if not cmd then
			return nil, nil, nil
		end
	end
	local cmdn = clusterp:tag(cmd)
	return cmdn, clusterp:encode(cmd, body, true)
end

local rpc
local fd_to_uuid = {}
local uuid_to_fd = {}
local fd_to_desc = {}
local capacity = {}
local establish_fn = nop

local function close_uuid(uuid)
	local fd = uuid_to_fd[uuid]
	if fd then
		uuid_to_fd[uuid] = nil
		fd_to_uuid[fd] = nil
		fd_to_desc[fd] = nil
		rpc.close(fd)
	end
end

local function establish_uuid(name, uuid, fd)
	close_uuid(uuid)
	uuid_to_fd[uuid] = fd
	fd_to_uuid[fd] = uuid
	logger.info("[cluster]", name, "establish uuid:", uuid, "fd:", fd)
	establish_fn(name, uuid, fd)
end

local event_addr

local id_hello_r = clusterp:tag("hello_r")
rpc = cluster.new {
	marshal = marshal,
	unmarshal = unmarshal,
	call = function(body, cmd, fd)
		local uuid = fd_to_uuid[fd]
		if uuid then
			return router[cmd](body, uuid)
		elseif cmd == id_hello_r then	--handshake
			uuid = body.id
			local name = body.name
			establish_uuid(name, uuid, fd)
			logger.info("[cluster]", args.service, "recv hello_r from", name, uuid)
			return body
		else
			logger.error("[cluster] call unkonw cmd:", cmd)
		end
	end,
	accept = function(fd, addr)
		logger.info("[cluster] accept fd:", fd, "addr:", addr)
	end,
	close = function(fd, errno)
		local uuid = fd_to_uuid[fd]
		close_uuid(uuid)
		logger.info("[cluster] close fd:", fd, "errno:", errno)
		local desc = fd_to_desc[fd]
		if desc then
			core.fork(function()
				logger.info("[cluster] reconnect to", desc.name, "uuid:", uuid, "addr:", desc.addr)
				core.sleep(1000)
				event_addr(desc.name, uuid, desc.addr)
			end)
		end
	end,
}


function event_addr(name, uuid, addr)
	logger.debug("[cluster] event addr service:", name, "uuid:", uuid, "addr:", addr)
	if addr then
		local fd = rpc.connect(addr)
		if fd then
			local ack = rpc.call(fd, "hello_r", {
				id = uuid,
				name = args.service,
			})
			if ack then
				establish_uuid(name, uuid, fd)
				fd_to_desc[fd] = {
					name = name,
					addr = addr,
				}
				logger.info("[cluster] connect to", name, "uuid:", uuid, "addr:", addr, "success")
				return
			end
		end
		core.fork(function()
			core.sleep(1000)
			logger.error("[role] connect to", name, "uuid:", uuid, "addr:", addr, "fail, retry")
			event_addr(name, uuid, addr)
		end)
	else
		close_uuid(uuid)
	end
end

local M = {capacity = capacity}
function M.send(uuid, cmd, obj)
	local fd = uuid_to_fd[uuid]
	if not fd then
		logger.error("[cluster] send to service:", uuid,
			"cmd:", cmd, "obj:", obj, "error")
		return false
	end
	return rpc.send(fd, cmd, obj)
end

function M.call(uuid, cmd, obj)
	local fd = uuid_to_fd[uuid]
	if not fd then
		logger.error("[cluster] call service:", uuid,
			"cmd:", cmd, "obj:", obj, "error")
		return nil, "closed"
	end
	return rpc.call(fd, cmd, obj)
end

--fn(name, uuid, fd)
function M.watch_establish(fn)
	establish_fn = fn
end

function M.connect(name)
	local desc = conf.get(name)
	if not desc then
		logger.error("[cluster] get conf:", name, "error")
		return cleanup()
	end
	capacity[name] = desc.capacity
	conf.watch(name, function (id, addr)
		local uuid = serviceid.uuid(name, id)
		event_addr(name, uuid, addr)
	end)
	for id, addr in ipairs(desc) do
		local uuid = serviceid.uuid(name, id)
		event_addr(name, uuid, addr)
	end
end

function M.listen(addr)
	local ok, err = rpc.listen(addr)
	if not ok then
		logger.error("[", args.service, "] listen addr:", addr, "error:", err)
		return cleanup()
	end
	return true
end

return M

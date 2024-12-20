local core = require "core"
local mutex = require "core.sync.mutex"
local code = require "lib.code"
local cleanup = require "lib.cleanup".exec
local args = require "lib.args"
local logger = require "core.logger"
local cluster = require "core.cluster"
local conf = require "lib.conf.service"
local node = require "lib.conf.node"
local ipairs = ipairs
local assert = assert


--- @type core.cluster
local rpc
local event_addr
local connect_lock = mutex:new()
local fd_to_nodeid = {}
local nodeid_to_fd = {}
local capacity = {}
local nodeid_to_desc = {}

local function nop(...) end
local establish_fn = nop

local function dummy_handler(_, nodeid)
	logger.error("[cluster] nodeid:", nodeid)
	return {
		code = code.maintain,
	}
end
local router = setmetatable({}, {
	__index = function(t, k)
		return dummy_handler
	end,
})

local function close_node(nodeid)
	local fd = nodeid_to_fd[nodeid]
	if fd then
		nodeid_to_fd[nodeid] = nil
		fd_to_nodeid[fd] = nil
		rpc.close(fd)
	end
end

local function establish_node(desc, fd)
	if desc.changed then
		rpc.close(fd)
		logger.warn("[cluster] establish node:", desc.service,
			desc.workerid, "fd:", fd, "changed")
		return
	end
	local nodeid = desc.nodeid
	if nodeid_to_fd[desc.nodeid] == fd then
		return
	end
	close_node(nodeid)
	nodeid_to_fd[nodeid] = fd
	fd_to_nodeid[fd] = nodeid
	logger.info("[cluster] establish node:", desc.service, desc.workerid, "fd:", fd)
	establish_fn(desc.service, nodeid, fd)
end

function event_addr(desc)
	local handle<close> = connect_lock:lock(desc)
	if desc.changed then --if addr changed, close the old fd first
		desc.changed = nil
		close_node(desc.nodeid)
	end
	if not desc.addr then	--if has no addr, there is no need to connect
		return
	end
	local name = desc.name
	local addr = desc.addr
	local workerid = desc.workerid
	logger.debug("[cluster] event addr service:", name,
		"workerid:", workerid, "addr:", addr)
	local fd, err = rpc.connect(addr)
	if not fd then
		logger.error("[cluster] connect to", name, "workerid:", workerid, "addr:", addr, "error:", err)
		core.fork(function()
			core.sleep(1000)
			logger.error("[cluster] reconnect to", name, "workerid:", workerid, "addr:", addr)
			event_addr(desc)
		end)
		return
	end
	local ack = rpc.call(fd, "hello_r", {
		service = args.service,
		workerid = node.workerid,
	})
	if ack then
		establish_node(desc, fd)
		logger.info("[cluster] connect to", name, "workerid:", workerid, "addr:", addr, "success")
	end
end

local M = {capacity = capacity}
function M.send(nodeid, cmd, obj)
	local fd = nodeid_to_fd[nodeid]
	if not fd then
		logger.error("[cluster] send to service:", nodeid,
			"cmd:", cmd, "obj:", obj, "error")
		return false
	end
	return rpc.send(fd, cmd, obj)
end

function M.call(nodeid, cmd, obj)
	local fd = nodeid_to_fd[nodeid]
	if not fd then
		logger.error("[cluster] call service:", nodeid,
			"cmd:", cmd, "obj:", obj, "error")
		return nil, "closed"
	end
	return rpc.call(fd, cmd, obj)
end

--fn(name, nodeid, fd)
function M.watch_establish(fn)
	establish_fn = fn
end

local function add_node_desc(name, workerid, addr)
	local nodeid = node.id(name, workerid)
	local desc = nodeid_to_desc[nodeid]
	if not desc then
		desc = {
			name = name,
			workerid = workerid,
			nodeid = nodeid,
			addr = nil,
			changed = nil,
		}
		nodeid_to_desc[nodeid] = desc
	end
	if addr then
		if desc.addr ~= addr then
			desc.addr = addr
			desc.changed = true
		end
		nodeid_to_desc[nodeid] = desc
	else
		if desc.addr ~= nil then
			desc.addr = nil
			desc.changed = true
		end
		nodeid_to_desc[nodeid] = nil
	end
	return desc
end

function M.start(marshal, unmarshal)
 	local id_hello_r, _ = marshal("request", "hello_r", {})

	rpc = cluster.new {
		marshal = assert(marshal),
		unmarshal = assert(unmarshal),
		call = function(body, cmd, fd)
			if cmd == id_hello_r then	--handshake
				local service = body.service
				local workerid = body.workerid
				logger.info("[cluster]", args.service,
					"recv hello_r from", service, workerid)
				local desc = {
					service = service,
					workerid = workerid,
					nodeid = node.id(service, workerid),
				}
				establish_node(desc, fd)
				return body
			end
			local nodeid = fd_to_nodeid[fd]
			if nodeid then
				local ack = router[cmd](body, nodeid)
				--logger.debug("[cluster] call cmd:", cmd, "fd:", fd, "req", body, "ack:", ack)
				return ack
			end
			logger.error("[cluster] call cmd:", cmd, "fd:", fd, "error")
			return nil
		end,
		accept = function(fd, addr)
			logger.info("[cluster] accept fd:", fd, "addr:", addr)
		end,
		close = function(fd, errno)
			local nodeid = fd_to_nodeid[fd]
			close_node(nodeid)
			local desc = nodeid_to_desc[nodeid]
			logger.info("[cluster] close fd:", fd, "errno:", errno, desc)
			if not desc then
				return
			end
			core.fork(function()
				logger.info("[cluster] reconnect to", desc.name,
					"workerid:", desc.workerid, "addr:", desc.addr)
				core.sleep(1000)
				event_addr(desc)
			end)
		end,
	}
end

function M.connect(name)
	logger.info("[cluster] connect to", name)
	local service_desc = conf.get(name)
	if not service_desc then
		logger.error("[cluster] get conf:", name, "error")
		return cleanup()
	end
	capacity[name] = service_desc.capacity
	conf.watch(name, function (workerid, addr)
		event_addr(add_node_desc(name, workerid, addr))
	end)
	for workerid, addr in ipairs(service_desc) do
		event_addr(add_node_desc(name, workerid, addr))
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

function M.serve(router_table)
	router = router_table
end

function M.nodeids(name)
	local service = conf.get(name)
	if not service then
		return nil
	end
	return node.ids(name, 1, service.capacity)
end

return M

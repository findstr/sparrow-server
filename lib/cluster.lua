local core = require "core"
local code = require "lib.code"
local cleanup = require "lib.cleanup"
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

local function establish_node(service, workerid, fd)
	local nodeid = node.id(service, workerid)
	if nodeid_to_fd[nodeid] == fd then
		return
	end
	close_node(nodeid)
	nodeid_to_fd[nodeid] = fd
	fd_to_nodeid[fd] = nodeid
	logger.info("[cluster] establish node:", service, workerid, "fd:", fd)
	establish_fn(service, nodeid, fd)
end

function event_addr(nodeid, addr)
	local desc = nodeid_to_desc[nodeid]
	if desc then
		local name = desc.name
		local addr = desc.addr
		local workerid = desc.workerid
		logger.debug("[cluster] event addr service:", name,
			"workerid:", workerid, "addr:", addr)
		local fd = rpc.connect(addr)
		if fd then
			local ack = rpc.call(fd, "hello_r", {
				service = args.service,
				workerid = node.workerid,
			})
			if ack then
				establish_node(name, workerid, fd)
				logger.info("[cluster] connect to", name, "workerid:", workerid, "addr:", addr, "success")
				return
			end
		end
		core.fork(function()
			core.sleep(1000)
			logger.error("[role] connect to", name, "nodeid:", workerid, "addr:", addr, "fail, retry")
			event_addr(nodeid, addr)
		end)
	else
		assert(addr)
		rpc.close(addr)
		close_node(nodeid)
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
	if addr then
		nodeid_to_desc[nodeid] = {
			name = name,
			addr = addr,
			workerid = workerid,
		}
		logger.info("[cluster] add node desc:", name, workerid, addr)
	else
		local desc = nodeid_to_desc[nodeid]
		if desc then
			addr = desc.addr
		end
		nodeid_to_desc[nodeid] = nil
		logger.info("[cluster] del node desc:", name, workerid)
	end
	return nodeid, addr
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
				establish_node(service, workerid, fd)
				return body
			end
			local nodeid = fd_to_nodeid[fd]
			if nodeid then
				return router[cmd](body, nodeid)
			end
			logger.error("[cluster] call cmd:", cmd, "fd:", fd, "error")
			return nil
		end,
		accept = function(fd, addr)
			logger.info("[cluster] accept fd:", fd, "addr:", addr)
		end,
		close = function(fd, errno)
			local nodeid = fd_to_nodeid[fd]
			local desc = nodeid_to_desc[nodeid]
			close_node(nodeid)
			logger.info("[cluster] close fd:", fd, "errno:", errno, desc)
			if not desc then
				return
			end
			core.fork(function()
				logger.info("[cluster] reconnect to", desc.name,
					"workerid:", desc.workerid, "addr:", desc.addr)
				core.sleep(1000)
				event_addr(nodeid, desc.addr)
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

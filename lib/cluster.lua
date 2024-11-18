local core = require "core"
local cleanup = require "lib.cleanup"
local router = require "lib.router.cluster"
local args = require "lib.args"
local logger = require "core.logger"
local cluster = require "core.cluster"
local conf = require "lib.conf.service"
local callretp = require "app.proto.callret"
local clusterp = require "app.proto.cluster"
local assert = assert
local ipairs = ipairs

local callret = callretp(clusterp)
local function nop() end
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

local id_to_close = {}
local fd_to_id = {}
local cluster_rpc = cluster.new {
	marshal = marshal,
	unmarshal = unmarshal,
	call = function(body, cmd, fd)
		local id = fd_to_id[fd]
		return router[cmd](body, id)
	end,
	accept = function(fd, addr)
		fd_to_id[fd] = fd
		logger.info("[cluster] accept fd:", fd, "addr:", addr)
	end,
	close = function(fd, errno)
		local id = fd_to_id[fd]
		local fn = id_to_close[id]
		if fn then
			fn(id, errno)
		end
	end,
}

local service = {}
local service_mt = {__index = service}
function service:event_addr(id, addr)
	local name = self.name
	local rpc = self.rpc
	self.id_to_addr[id] = addr
	logger.debug("[cluster] event addr service:", name, "id:", id, "addr:", addr)
	if addr then
		local fd = rpc.connect(addr)
		if fd then
			local ack = rpc.call(fd, "hello_r", {
				id = id,
				name = args.service,
			})
			if ack then
				self:event_establish(name, id, fd)
				logger.info("[cluster] connect to id:", id, "addr:", addr, "success")
				return
			end
		end
		core.fork(function()
			core.sleep(1000)
			logger.error("[role] connect to id:", id, "addr:", addr, "fail, retry")
			self:event_addr(id, addr)
		end)
	else
		self:close(id)
	end
end

function service:close(id)
	local fd = self.id_to_fd[id]
	if fd then
		id_to_close[id] = nil
		fd_to_id[fd] = nil
		self.id_to_fd[id] = nil
		self.rpc.close(fd)
	end
end

function service:event_close(id, errno)
	self.id_to_fd[id] = nil
	local addr = self.id_to_addr[id]
	logger.error("[cluster]", self.name, "event_close id:", id, "errno:", errno)
	core.fork(function()
		self:event_addr(id, addr)
	end)
end

function service:event_establish(name, id, fd)
	self:close(id)	--try clear old connections
	id_to_close[id] = self.onclose
	fd_to_id[fd] = id
	self.id_to_fd[id] = fd
	self.establish(name, id, fd)
	logger.info("[cluster]", self.name, "establish id:", id, "fd:", fd)
end

function service:send(id, cmd, obj)
	local fd = self.id_to_fd[id]
	if not fd then
		logger.error("[cluster] send service:", self.name, "id:", 
			id, "cmd:", cmd, "obj:", obj, "error")
		return false
	end
	return self.rpc.send(fd, cmd, obj)
end

function service:call(id, cmd, obj)
	local fd = self.id_to_fd[id]
	if not fd then
		logger.error("[cluster] call service:", self.name, "id:", 
			id, "cmd:", cmd, "obj:", obj, "error")
		return nil, "closed"
	end
	return self.rpc.call(fd, cmd, obj)
end

local services = setmetatable({}, {__index = function(t, k)
	local c
	assert(k)
	c = setmetatable({
		--placeholder
		capacity = 0,
		onconnect = nop,
		--public init
		name = k,
		id_to_fd = {},
		id_to_addr = {},
		onclose = function(id, errno)
			c:event_close(id, errno)
		end,
		rpc = cluster_rpc,
	}, service_mt)
	t[k] = c
	return c
end})


local M = { services = services }

function M.connect(name, establish)
	local desc = conf.get(name)
	if not desc then
		logger.error("[%s] get conf error")
		return cleanup()
	end
	local srv = services[name]
	srv.capacity = desc.capacity
	srv.establish = establish
	conf.watch(srv, function (id, addr)
		srv:event_addr(id, addr)
	end)
	for id, addr in ipairs(desc) do
		srv:event_addr(id, addr)
	end
	return srv
end

function M.listen(addr, establish)
	router.hello_r = function(req, id)
		local fd = fd_to_id[id]
		fd_to_id[id] = nil	--clear the `accept` workaround
		assert(fd == id)
		local service = services[req.name]
		assert(service.id_to_fd[id] ~= fd)
		service.establish = establish
		service:event_establish(req.name, req.id, fd)
		logger.info("[cluster]", args.service, "recv hello_r from", req.name, req.id)
		return req
	end
	local ok, err = cluster_rpc.listen(addr)
	if not ok then
		logger.error("[scene] listen addr:", addr, "error:", err)
		return cleanup()
	end
	return true
end

return M

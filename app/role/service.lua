local json = require "core.json"
local logger = require "core.logger"
local cluster = require "core.cluster"
local callret = require "app.proto.callret"
local clusterp = require "app.proto.cluster"
local crouter = require "lib.router.cluster"
local grouter = require "lib.router.gateway"

local function unmarshal(cmd, buf, sz)
	return clusterp:decode(cmd, buf, sz)
end

local function marshal(cmd, body)
	cmd = clusterp:tag(cmd)
	return cmd, clusterp:encode(cmd, body)
end

local serve = cluster.new {
	callret = callret(clusterp),
	marshal = marshal,
	unmarshal = unmarshal,
	call = function(body, cmd, fd)
		return crouter[cmd](body, fd)
	end,
	close = function(fd, errno)
	end,
}

function crouter.hello_r(req)
	logger.info("[role] hello_r", req.name, req.id)
	assert(req.name == "gateway", req.name)
	return {}
end

function crouter.forward_r(req, fd)
	local cmd = req.cmd
	local fn = grouter[cmd]
	if not fn then
		logger.error("[role] forward_r uid:", req.uid, "cmd:", cmd, "not found")
		return nil
	end
	local ack = fn(req.uid, req.body, fd)
	if ack then
		return {body = json.encode(ack)}
	end
	return nil
end

return serve

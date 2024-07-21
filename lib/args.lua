local env = require "core.env"
local assert = assert

local serviceid = {
	gateway = 1,
	role = 2,
}

local service = assert(env.get("service"), "service")

local M = {
	etcd = assert(env.get("etcd"), "etcd"),
	listen = assert(env.get("listen"), "listen"),
	service = service,
	workerid = env.get("workerid"),
	serviceid = assert(serviceid[service], service),
}

return M
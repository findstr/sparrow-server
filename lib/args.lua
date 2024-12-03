local env = require "core.env"
local service = assert(env.get("service"), "service")

local assert = assert

local M = {
	etcd = assert(env.get("etcd"), "etcd"),
	listen = assert(env.get("listen"), "listen"),
	service = service,
	workerid = env.get("workerid"),
}

return M
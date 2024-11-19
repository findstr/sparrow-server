local env = require "core.env"
local serviceid = require "lib.serviceid"
local service = assert(env.get("service"), "service")

local assert = assert

local M = {
	etcd = assert(env.get("etcd"), "etcd"),
	listen = assert(env.get("listen"), "listen"),
	service = service,
	workerid = env.get("workerid"),
	serviceid = assert(serviceid.get(service), service),
}

return M
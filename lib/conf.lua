local etcd = require "core.etcd"
local logger = require "core.logger"
local args = require "lib.args"
local cleanup = require "lib.cleanup".clean
local service = require "lib.conf.service"
local node = require "lib.conf.node"
local serverlist = require "lib.conf.serverlist"

local etcd_client

local M = {}
function M.start()
	etcd_client = etcd.newclient {
		retry = 5,
		retry_sleep = 1000,
		endpoints = {args.etcd},
		timeout = 5000,
	}
	local res, err = etcd_client:grant {
		TTL = 5,
	}
	if not res then
		logger.error("[conf.workerid] etcd grant failed:", err)
		return cleanup()
	end
	local lease_id = res.ID
	serverlist.start(etcd_client)
	service.start(etcd_client)
	node.start(etcd_client, lease_id)
end


return M

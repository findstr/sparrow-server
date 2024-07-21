local core = require "core"
local json = require "core.json"
local logger = require "core.logger"

local M = {}

local etcd
local key_prefix<const> = "/serverlist/"
local serverlist = {}

local function process_event(event, kv)
	local key = kv.key
	local id = key:match("/serverlist/(%g+)")
	if not id then
		logger.error("[lib.conf.serverlist] invalid key:", key)
		return
	end
	local idnum = tonumber(id)
	if not idnum then
		logger.error("[lib.conf.serverlist] invalid id:", id)
		return
	end
	if event == "DELETE" then
		serverlist[idnum] = nil
		logger.error("[lib.conf.serverlist] server:", key, "deleted")
		return
	end
	local desc = kv.value
	local obj = json.decode(desc)
	if not obj then
		logger.error("[lib.conf.serverlist] invalid desc:", desc, "server:", key)
		return
	end
	serverlist[idnum] = {
		id = idnum,
		name = obj.name,
		opentime = obj.opentime,
	}
	logger.info("[lib.conf.serverlist] server id:", key, "desc:", desc)
end

local function watch_loop(stream)
	while true do
		local res, err = stream:read()
		if not res then
			logger.error("[core.etcd] watch workerid failed:", err)
			return
		end
		for _, event in ipairs(res.events) do
			process_event(event.type, event.kv)
		end
	end
end

local function watch_modify(etcd, prefix)
	return function()
		while true do
			local stream, err = etcd:watch {
				key = prefix,
			}
			if stream then
				watch_loop(stream)
				stream:close()
			else
				logger.error("[lib.conf.service] watch failed:", err)
				core.sleep(1000)
			end
		end
	end
end

function M.start(etcd_client)
	etcd = etcd_client
	local res, err = etcd:get {
		key = key_prefix,
		prefix = true,
	}
	if not res or #res.kvs == 0 then
		logger.error("[lib.conf.serverlist] get", key_prefix, "failed:", err)
		return nil
	end
	for _, kv in ipairs(res.kvs) do
		process_event('PUT', kv)
	end
	core.fork(watch_modify(etcd, key_prefix))
end

function M.get()
	return serverlist
end

return M
local core = require "core"
local json = require "core.json"
local logger = require "core.logger"
local cleanup = require "lib.cleanup"

local M = {}

local etcd
local service_prefix<const> = "/service"
local service_desc = {}
local care_service = {}
local monitor = {}

local function process_event(event, kv)
	local key = kv.key
	local service, typ, id = key:match("/service/([^/]+)/([^/]+)/?(%g*)")
	if not service then
		logger.error("[lib.conf.service] invalid key:", key)
		return
	end
	if not care_service[service] then
		return
	end
	local desc = service_desc[service]
	if not desc then
		desc = {}
		service_desc[service] = desc
	end
	if typ == "capacity" then
		if event == "DELETE" then
			logger.error("[lib.conf.service] service:", key, "deleted")
			cleanup()
			return
		end
		local val = kv.value
		local cap = tonumber(val)
		if not cap then
			logger.error("[lib.conf.service] invalid capacity:", val)
			return
		end
		if not desc.capacity then
			desc.capacity = cap
		elseif desc.capacity ~= cap then
			logger.error("[core.etcd] service capacity changed:",
				desc.capacity, "to", cap)
			cleanup()
			return
		end
	elseif typ == "instance" then
		id = tonumber(id) + 1
		if not id then
			logger.error("[core.etcd] invalid service instance id:", id)
			return
		end
		if event == "DELETE" then
			desc[id] = nil
			local fn = monitor[service]
			if fn then
				fn(id, nil)
			end
		else
			local val = kv.value
			desc[id] = val
			local fn = monitor[service]
			if fn then
				fn(id, val)
			end
		end
	else
		logger.error("[lib.conf.service] invalid key:", key)
	end
end

local function watch_loop(stream)
	while true do
		local res, err = stream:read()
		if not res then
			logger.error("[core.etcd] watch workerid failed:", err)
			return
		end
		for _, event in ipairs(res.events) do
			core.fork(function()
				process_event(event.type, event.kv)
			end)
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
end

function M.watch(service, fn)
	monitor[service] = fn
end

function M.get(service)
	local desc = service_desc[service]
	if desc then
		return desc
	end
	care_service[service] = true
	local prefix = service_prefix .. "/" .. service
	local res, err = etcd:get {
		key = prefix,
		prefix = true,
	}
	if not res or #res.kvs == 0 then
		logger.error("[lib.conf.service] get", prefix, "failed:", err)
		return nil
	end
	for _, kv in ipairs(res.kvs) do
		process_event('PUT', kv)
	end
	core.fork(watch_modify(etcd, prefix))
	return service_desc[service]
end

return M

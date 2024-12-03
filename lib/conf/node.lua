local core = require "core"
local logger = require "core.logger"
local args = require "lib.args"
local cleanup = require "lib.cleanup"

local M = {}

local tonumber = tonumber
local sort = table.sort
local service_shift<const> = 10000			--serviceid as the most significant digit in decimal.
local service_max<const> = 8 * service_shift		--serviceid can't large than '8' in decimal.
--NOTE: nodeid = serviceid * service_shift + workerid
local serviceid = {
	gateway = 0,
	role = 1,
	scene = 2,
}
do
	for _, v in pairs(serviceid) do
		if v >= service_max then
			logger.error("[lib.conf.node] serviceid overflow:", v)
			cleanup()
		end
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
			if event.type == "DELETE" then
				logger.error("[core.etcd] workerid deleted key:", event.kv.key)
				cleanup()
				return
			elseif event.kv.value ~= args.listen then
				logger.error("[core.etcd] workerid changed key:",
					event.kv.key, "from", args.listen, "to", event.kv.value)
				cleanup()
				return
			end
		end
	end
end

local function watch_self(etcd, key)
	return function()
		while true do
			local stream, err = etcd:watch {
				key = key,
			}
			if stream then
				watch_loop(stream)
				stream:close()
			else
				logger.error("[lib.conf.node] watch workerid failed:", err)
				core.sleep(1000)
			end
		end
	end
end

function M.id(service, workerid)
	if workerid >= service_shift then
		logger.error("[lib.conf.node] worker_id overflow:", workerid)
		cleanup()
	end
	local sid = serviceid[service]
	return sid * service_shift + workerid
end

function M.selfid()
	return M.id(M.service, M.workerid)
end

function M.start(etcd, lease_id)
	local uuid = args.listen
	local service = args.service
	local workerid = args.workerid
	M.service = service
	if workerid then
		local service_key = "/service/" .. service .. "/worker/" .. workerid
		local res, err = etcd:put {
			key = service_key,
			value = uuid,
			lease = lease_id,
			prev_kv = true,
		}
		if not res then
			logger.error("[lib.conf.node] etcd put service failed:", err)
			return cleanup()
		end
		M.workerid = workerid
		logger.info("[lib.conf.node] service:", service, "workerid:", workerid)
		return
	end
	local lock_prefix = "/lock/" .. args.service
	local res, err = etcd:lock(lease_id, lock_prefix, uuid)
	if not res then
		logger.error("[lib.conf.node] lock fail:", err)
		cleanup()
	end
	local service_prefix = "/service/" .. args.service .. "/worker"
	res, err = etcd:get {
		key = service_prefix,
		prefix = true
	}
	if not res then
		logger.error("[lib.conf.node] etcd get service failed:", err)
		cleanup()
	end
	local kvs = res.kvs
	sort(kvs, function(a, b)
		return a.key < b.key
	end)
	local findself = false
	workerid = 1
	for _, kv in ipairs(kvs) do
		local id = tonumber(kv.key:match("(%d+)$"))
		if kv.value == uuid then
			findself = true
			workerid = id
			break
		end
		if id == workerid then
			workerid = id + 1
		else
			break
		end
	end
	local service_key = "/service/" .. args.service .. "/worker/" .. workerid
	res, err = etcd:put {
		key = service_key,
		value = uuid,
		lease = lease_id,
		prev_kv = true,
	}
	etcd:unlock(lock_prefix, uuid)
	if not res or (res.prev_kv and res.prev_kv.value ~= uuid) then
		logger.error("[lib.conf.node] etcd put service failed:", err, "prev_kv:", res and res.prev_kv)
		cleanup()
	end
	M.workerid = workerid
	core.fork(watch_self(etcd, service_key))
	logger.info("[lib.conf.node] service:", service, "workerid:", workerid)
end

return M
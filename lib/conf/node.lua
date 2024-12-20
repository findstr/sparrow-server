local core = require "core"
local logger = require "core.logger"
local args = require "lib.args"
local cleanup = require "lib.cleanup"

local M = {}

local assert = assert
local tonumber = tonumber
local sort = table.sort
local service_shift<const> = 10000			--serviceid as the most significant digit in decimal.
local service_max<const> = 8 * service_shift		--serviceid can't large than '8' in decimal.
--NOTE: nodeid = serviceid * service_shift + workerid
local serviceid = {
	gateway = 1,
	role = 2,
	scene = 3,
}
do
	for _, v in pairs(serviceid) do
		if v >= service_max then
			logger.error("[lib.conf.node] serviceid overflow:", v)
			cleanup.exec()
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
				cleanup.exec()
				return
			elseif event.kv.value ~= args.listen then
				logger.error("[core.etcd] workerid changed key:",
					event.kv.key, "from", args.listen, "to", event.kv.value)
				cleanup.exec()
				return
			end
		end
	end
end

local function watch_self(etcd, key)
	return function()
		assert(M.workerid)
		while true do
			local stream, err = etcd:watch {
				key = key,
			}
			if not M.workerid then	--worker已经关闭了
				return
			end
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
		cleanup.exec()
	end
	local sid = serviceid[service]
	return sid * service_shift + workerid
end

local function iter_ids(to, from)
	if from >= to then
		return nil
	end
	from = from + 1
	return from
end

function M.ids(service, from ,to)
	local from_id = M.id(service, from)
	local to_id = M.id(service, to)
	return iter_ids, to_id, from_id - 1, nil
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
			return cleanup.exec()
		end
		M.workerid = workerid
		logger.info("[lib.conf.node] service:", service, "workerid:", workerid)
		return
	end
	local lock_prefix = "/lock/" .. args.service
	local res, err = etcd:lock(lease_id, lock_prefix, uuid)
	if not res then
		logger.error("[lib.conf.node] lock fail:", err)
		cleanup.exec()
	end
	local service_prefix = "/service/" .. args.service .. "/worker"
	res, err = etcd:get {
		key = service_prefix,
		prefix = true
	}
	if not res then
		logger.error("[lib.conf.node] etcd get service failed:", err)
		cleanup.exec()
	end
	local kvs = res.kvs
	sort(kvs, function(a, b)
		return a.key < b.key
	end)
	workerid = 1
	for _, kv in ipairs(kvs) do
		local id = tonumber(kv.key:match("(%d+)$"))
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
		cleanup.exec()
	end
	M.workerid = workerid
	cleanup.atexit(function()
		local workerid = M.workerid
		if not workerid then
			return
		end
		M.workerid = nil
		local res, err = etcd:delete {
			key = service_key,
			prev_kv = true,
		}
		if not res then
			logger.error("[lib.conf.node] etcd delete service failed:", err)
		end
		logger.info("[lib.conf.node] service:", service, "cleanup workerid:", workerid)
	end)
	core.fork(watch_self(etcd, service_key))
	logger.info("[lib.conf.node] service:", service, "workerid:", workerid)
end

return M

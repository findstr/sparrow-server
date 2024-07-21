local core = require "core"
local logger = require "core.logger"
local args = require "lib.args"
local cleanup = require "lib.cleanup"

local M = {}

local tonumber = tonumber
local sort = table.sort
local serivce_shift<const> = 9		--serviceid as low 3 bits of 14 bits
--NOTE: workerid = serviceid << service_shift + instanceid
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
				logger.error("[lib.conf.workerid] watch workerid failed:", err)
				core.sleep(1000)
			end
		end
	end
end
function M.start(etcd, lease_id)
	local uuid = args.listen
	local id = args.workerid
	if id then
		local service_key = "/service/" .. args.service .. "/instance/" .. id
		local res, err = etcd:put {
			key = service_key,
			value = uuid,
			lease = lease_id,
			prev_kv = true,
		}
		if not res then
			logger.error("[lib.conf.workerid] etcd put service failed:", err)
			return cleanup()
		end
		M.id = tonumber(id)
		logger.info("[lib.conf.workerid] workerid:", M.id)
		return
	end
	local lock_prefix = "/lock/" .. args.service
	local res, err = etcd:lock(lease_id, lock_prefix, uuid)
	if not res then
		logger.error("[lib.conf.workerid] lock fail:", err)
		cleanup(1)
	end
	local service_prefix = "/service/" .. args.service .. "/instance"
	local res, err = etcd:get {
		key = service_prefix,
		prefix = true
	}
	if not res then
		logger.error("[lib.conf.workerid] etcd get service failed:", err)
		cleanup(1)
	end
	local kvs = res.kvs
	sort(kvs, function(a, b)
		return a.key < b.key
	end)
	local instanceid = 0
	for _, kv in ipairs(kvs) do
		local id = tonumber(kv.key:match("(%d+)$"))
		if id == instanceid then
			instanceid = id + 1
		else
			break
		end
	end
	local service_key = "/service/" .. args.service .. "/instance/" .. instanceid
	local res, err = etcd:put {
		key = service_key,
		value = uuid,
		lease = lease_id,
		prev_kv = true,
	}
	etcd:unlock(lock_prefix, uuid)
	if not res or res.prev_kv then
		logger.error("[lib.conf.workerid] etcd put service failed:", err, "prev_kv:", res and res.prev_kv)
		cleanup()
	end
	if instanceid >= (1 << serivce_shift) then
		logger.error("[lib.conf.workerid] instance_id overflow:", instanceid)
		cleanup()
	end
	local serviceid = args.serviceid
	M.id = (serviceid << serivce_shift) + instanceid
	core.fork(watch_self(etcd, service_key))
	logger.info("[lib.conf.workerid] serviceid:", serviceid, "instanceid:", instanceid, "workerid:", M.id)
end

return M

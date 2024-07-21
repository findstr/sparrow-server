local core = require "core"
local dns = require "core.dns"
local logger = require "core.logger"
local redis = require "core.db.redis"
local service = require "lib.conf.service"
local worker = require "lib.conf.worker"
local cleanup = require "lib.cleanup"


local tonumber = tonumber
local byte = string.byte

local M = {}
local db_cap
local db_pool = {}
local db_addr = {}

local db_timer_period <const> = 1000	--ms

local guid_bits<const> = 64
local workerid_bits<const> = 14
local workerid_shift<const> = guid_bits - workerid_bits

local dbk_guid<const> = "_guid"

local guid_db
local guid_key
local guid_alloc_idx
local guid_block_begin
local guid_block_end
local guid_block<const> = 1000
local guid_half_block<const> = guid_block // 2
local dbk_hash = setmetatable({}, {__index = function(t, k)
	local len = #k
	if len == 0 then
		return 1
	end
	local n = byte(k, #k)
	n = n % db_cap + 1
	t[k] = n
	return n

end})

local function db_timer()
	for i, db in ipairs(db_pool) do
		local ok, err = db:ping()
		if not ok then
			logger.error("[lib.db] db ping err:", db_addr[i], err)
		end
	end
end
local function init_guid()
	local workerid = worker.id
	if workerid >= (1 << workerid_bits) then
		logger.error("[lib.db] init_guid workerid:", workerid, "too large")
		cleanup()
	end
	guid_key = tostring(workerid)
	guid_db = db_pool[dbk_hash[dbk_guid]]
	local ok, id = guid_db:hget(dbk_guid, guid_key)
	if not ok then
		logger.error("[lib.db] init_guild can't fetch guid_start, err:", id)
		cleanup()
		return
	end
	guid_block_begin = workerid << workerid_shift
	if id then
		id = tonumber(id)
		if id <= guid_block_begin then
			logger.error("[lib.db] init_guild guid_start:", id, "too small, start:", guid_block_begin)
			cleanup()
			return
		end
		guid_block_begin = id
	end
	guid_alloc_idx = guid_block_begin
	guid_block_end = guid_block_begin + guid_block
	local ok, res = guid_db:hset(dbk_guid, guid_key, guid_block_end)
	if not ok then
		logger.error("[lib.db] init_guild can't set guid_start, err:", res)
		cleanup()
		return
	end
	logger.info("[lib.db] init_guid guid_alloc_idx:", guid_alloc_idx)
end

local safe_db_timer

safe_db_timer = function()
	local ok, err = core.pcall(db_timer)
	if not ok then
		logger.error("[lib.db] safe_db_timer err:", err)
	end
	core.timeout(db_timer_period, safe_db_timer)
end

local function init_db()
	local conf = service.get("db")
	if not conf then
		logger.error("[lib.db] no db service")
		return cleanup()
	end
	db_cap = conf.capacity
	if #conf ~= db_cap then
		logger.error("[libdb] init_db incorrect service instance, cap:",
			db_cap, "current:", #conf)
		return cleanup()
	end
	for i, addr in ipairs(conf) do
		db_addr[i] = addr
		local name, port = string.match(addr, "([^:]+):(%d+)")
		if dns.isname(name) then
			local ip = dns.lookup(name, dns.A, 5000)
			if not ip then
				logger.error("[lib.db] dns lookup failed:", name)
				return cleanup()
			end
			addr = ip .. ":" .. port
		end
		local db = redis:connect {
			addr = addr,
			db = 0,
		}
		local ok, res = db:set("_hashid", i, "nx", "get")
		if not ok then
			logger.info("[lib.db] set _hashid:", i, "err:", res)
			return cleanup()
		end
		if res and res ~= tostring(i) then
			logger.info("[lib.db] db:", addr, "_hashid mismatch:", res, i)
			return cleanup()
		end
		db_pool[i] = db
	end
	core.timeout(1000, safe_db_timer)
end

local function expand_guid_block()
	local ok, res = guid_db:hincrby(dbk_guid, guid_key, guid_block)
	if not ok then
		logger.error("[lib.db] expand_guid_block error:",
			res, "block", guid_block_begin)
		return false
	end
	local id = tonumber(res)
	if id < guid_alloc_idx then
		logger.error("[lib.db] expand_guid_block id:", id, "too small, start:", guid_alloc_idx)
		cleanup()
		return false
	end
	guid_block_end = id
	guid_block_begin = guid_block_end - guid_block
	return true
end

function M.start()
	init_db()
	init_guid()
end

function M.newid()
	local id = guid_alloc_idx
	guid_alloc_idx = id + 1
	if guid_alloc_idx + guid_half_block > guid_block_end then
		expand_guid_block()
	elseif guid_alloc_idx >= guid_block_end then
		local ok = false
		for i = 1, 100 do
			ok = expand_guid_block()
			if ok then
				break
			end
			core.sleep(50)
		end
		if not ok then
			logger.error("[lib.db] newid expand_guid_block failed, used:", id)
			cleanup()
			return
		end
	end
	return id
end

function M.hgetall(key, field)
	local db = db_pool[dbk_hash[key]]
	local ok, res = db:hgetall(key, field)
	if not ok then
		logger.error("[lib.db] hgetall error:", key, field, res)
	end
	return ok, res
end

function M.hget(key, field)
	local db = db_pool[dbk_hash[key]]
	local ok, res = db:hget(key, field)
	if not ok then
		logger.error("[lib.db] hget error:", key, field, res)
	end
	return ok, res
end

function M.hset(key, field, value)
	local db = db_pool[dbk_hash[key]]
	local ok, res = db:hset(key, field, value)
	if not ok then
		logger.error("[lib.db] hset", key, field, "err:", res)
	end
	return ok, res
end

function M.hsetnx(key, field, value)
	local db = db_pool[dbk_hash[key]]
	local ok, res = db:hsetnx(key, field, value)
	if not ok then
		logger.error("[lib.db] hsetnx error:", key, field, value, res)
	end
	return ok, res
end

return M

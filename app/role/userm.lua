local zproto = require "zproto"
local logger = require "core.logger"
local mutex = require "core.sync.mutex"
local db = require "lib.db"
local router = require "lib.router.gateway"
local code = require "app.code"
local service = require "app.role.service"

local assert = assert
local format = string.format
local dbk_user<const> = "u:%d"
local dbk_server_name<const> = "name:%d"

local uid_to_user = {}
local login_lock = mutex:new()

--TODO: add user evict timer

local dbp = assert(zproto:parse [[
	base {
		.uid:uint64 1
		.name:string 2
		.serverid:uinteger 3
	}
]])

local function load_user(uid)
	local ok, fields = db.hgetall(format(dbk_user, uid))
	if not ok then
		logger.error("[role] load uid:", uid, "err:", fields)
		return nil, code.internal_error
	end
	if #fields then
		logger.error("[role] load uid:", uid, "user not exist")
		return nil, code.user_not_exist
	end
	local u = {gate = nil}
	for i = 1, #fields, 2 do
		local k = fields[i]
		local v = fields[i + 1]
		local obj = dbp:decode(k, v)
		if not obj then
			logger.error("[role] load uid:", uid, "decode", k, v)
			return nil, code.internal_error
		end
		u[k] = obj
	end
	return u, nil
end

function router.login_r(uid, req, fd)
	local handle<close> = login_lock:lock(uid)
	local user = uid_to_user[uid]
	if user then
		local gate_fd = user.gate
		if gate_fd then
			local ack = service.kick_r(gate_fd, {
				uid = uid,
				code = code.login_others,
			})
			if not ack or ack.code then
				logger.error("[role] login_r kick uid:", uid, "err", ack and ack.code or "timeout")
				return {
					code = code.maintain,
				}
			end
		end
		user.gate = fd
	else
		local n
		user, n = load_user(uid)
		if not user then
			return {
				code = n,
			}
		end
		user.gate = fd
		uid_to_user[uid] = user
	end
	return {
		uid = uid,
	}
end

function router.create_r(uid, req, fd)
	local sid = req.server_id
	if not sid then
		logger.error("[role] create_r no uid:", uid, "sid:", sid)
		return
	end
	local handle<close> = login_lock:lock(uid)
	local user = uid_to_user[uid]
	if user then
		logger.error("[role] create_r sid:", sid, "uid:", uid, "exist")
		return {
			code = code.user_exist,
		}
	end
	local dbk_name = format(dbk_server_name, sid)
	local ok, n = db.hsetnx(dbk_name, req.name, uid)
	if not ok then
		logger.error("[role] create_r hsetnx", dbk_name, req.name, uid, "err:", n)
		return {
			code = code.internal_error,
		}
	end
	--[[
	if n == 0 then
		logger.error("[role] create_r sid:", sid, "uid:", req.uid, sid,
			"name:", req.name, "exist")
		return {
			code = code.user_name_repeated,	--玩家名字重复
		}
	end
	]]
	local base = {
		uid = uid,
		name = req.name,
		serverid = sid,
	}
	local data = dbp:encode("base", base)
	local ok, n = db.hsetnx(format(dbk_user, uid), base, data)
	if not ok then
		logger.error("[role] create_r set", dbk_user, uid, data, "err:", n)
		return {
			code = code.internal_error,
		}
	end
	if n == 0 then
		logger.error("[role] create_r uid:", uid, "exist")
		return {
			code = code.user_exist,
		}
	end
	local user = {
		gate = fd,
		base = {
			uid = uid,
			name = req.name,
			serverid = sid,
		},
	}
	uid_to_user[uid] = user
	logger.info("[role] create_r uid:", uid, "name:", req.name, "sid:", sid, "ok")
	return {
		uid = uid,
	}
end





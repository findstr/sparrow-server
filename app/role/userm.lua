local zproto = require "zproto"
local core = require "core"
local logger = require "core.logger"
local mutex = require "core.sync.mutex"
local waitgroup = require "core.sync.waitgroup"
local db = require "lib.db"
local router = require "app.router.gateway"
local code = require "app.code"

local assert = assert
local pairs = pairs
local format = string.format
local dbk_user <const> = "u:%d"
local dbk_server_name <const> = "name:%d"

local uid_to_user = require "app.role.online"
local login_lock = mutex:new()

--TODO: add user evict timer

local dbp = assert(zproto:parse [[
	base {
		.uid:uint64 1
		.name:string 2
		.serverid:uinteger 3
		.x:long 4
		.z:long 5
	}
]])

local M = {}

local function load_user(uid)
	local ok, fields = db.hgetall(format(dbk_user, uid))
	if not ok then
		logger.error("[role] load uid:", uid, "err:", fields)
		return nil, code.internal_error
	end
	if #fields == 0 then
		logger.error("[role] load uid:", uid, "user not exist")
		return nil, code.user_not_exist
	end
	local u = { gate = nil }
	for i = 1, #fields, 2 do
		local k = fields[i]
		local v = fields[i + 1]
		local obj = dbp:decode(k, v)
		if not obj then
			logger.error("[role] load uid:", uid, "decode", k, v)
			return nil, code.internal_error
		end
		logger.debug("[role] load uid:", uid, "k:", k, "v:", v)
		u[k] = obj
	end
	return u, nil
end


local cluster = require "lib.cluster"
function router.logout_r(uid, req, fd)
	--TODO:
end
function router.login_r(uid, req, fd)
	local handle <close> = login_lock:lock(uid)
	local user = uid_to_user[uid]
	if user then
		local gate_id = user.gate
		if gate_id then
			local ack = cluster.call(gate_id, "kick_r", {
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
	local base = user.base
	return {
		uid = uid,
		x = base.x,
		z = base.z,
	}
end

function router.create_r(uid, req, fd)
	local sid = req.server_id
	if not sid then
		logger.error("[role] create_r uid:", uid, "no sid:", sid)
		return {
			code = code.args_invalid
		}
	end
	local handle <close> = login_lock:lock(uid)
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
	local ok, n = db.hsetnx(format(dbk_user, uid), "base", data)
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
	local name = req.name
	local user = {
		gate = fd,
		base = {
			uid = uid,
			name = name,
			serverid = sid,
			x = 0,
			z = 0,
		},
	}
	uid_to_user[uid] = user
	logger.info("[role] create_r uid:", uid, "name:", req.name, "sid:", sid, "ok")
	return {
		uid = uid,
		name = name,
		x = 0,
		z = 0,
	}
end

local function restore_uids(uids)
	for _, uid in pairs(uids) do
		local u = load_user(uid)
		if u then
			uid_to_user[uid] = u
		end
	end
end

local function restore_gate(nodeid)
	local req = {}
        while true do
       		local ack = cluster.call(nodeid, "onlines_r", req)
        	if ack then
			restore_uids(ack.uids)
	 		logger.info("role onlines_r node:", nodeid,
				"uids:", table.concat(ack.uids, ","))
         		return
         	end
         	logger.error("role onlines_r node:", nodeid, "timeout")
         	core.sleep(1000)
        end
end

function M.restore()
	local group = waitgroup:create()
	for nodeid in cluster.nodeids("gateway") do
        	group:fork(function()
			restore_gate(nodeid)
        	end)
	end
	group:wait()
end

return M

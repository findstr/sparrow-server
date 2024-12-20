local json = require "core.json"
local logger = require "core.logger"
local cluster = require "lib.cluster"
local cleanup = require "lib.cleanup".exec
local db = require "lib.db"
local node = require "lib.conf.node"
local code = require "app.code"
local auth = require "app.gateway.auth"
local utils = require "app.gateway.utils"
local proto = require "app.proto.cluster"
local callret = require "app.proto.callret"
local crouter = require "app.router.cluster"
local grouter = require "app.router.gateway"

local format = string.format
local respond = utils.respond
local error = utils.error

local M = {}
local cap
local uid_to_sock = {}
local uid_to_nodeid = {}
local sock_to_uid = {}
local node_uid_set = setmetatable({}, {__index = function(t, k)
	local v = {}
	t[k] = v
	return v
end})
local dbk_uid = setmetatable({}, {
	__index = function(t, k)
		local dbk = format("uid:%d", k)
		t[k] = dbk
		return dbk
	end
})


local function establish(name, id, fd)
	logger.info("[gateway] establish", name, id, fd)
end

local function assign_node(uid)
	return node.id("role", uid % cap + 1)
end

local function login_success(uid, nodeid, sock)
	node_uid_set[nodeid][uid] = true
	uid_to_sock[uid] = sock
	uid_to_nodeid[uid] = nodeid
	sock_to_uid[sock] = uid
end

local function clear(sock)
	local uid = sock_to_uid[sock]
	if not uid then
		return
	end
	local nodeid = uid_to_nodeid[uid]
	if nodeid then
		uid_to_nodeid[uid] = nil
		node_uid_set[nodeid][uid] = nil
	end
	uid_to_sock[uid] = nil
	sock_to_uid[sock] = nil
end

local function logout(sock)
	local uid = sock_to_uid[sock]
	if not uid then
		return true
	end
	local nodeid = uid_to_nodeid[uid]
	if not nodeid then
		cleanup()
		return false
	end
	local ack = cluster.call(nodeid, "logout_r", {
		uid = uid,
	})
	if not ack then
		logger.error("[gateway] logout_r uid:", uid, "timeout")
		return false
	end
	if not ack.code then
		logger.error("[gateway] logout_r uid:", uid, "error", ack.code)
		return false
	end
	--error(sock, "logout_a", code.login_in_other)
	clear(sock)
end
local function forward(sock, cmd, body)
	local uid = sock_to_uid[sock]
	local nodeid = uid_to_nodeid[uid]
	if not uid then
		return nil
	end
	local ack = cluster.call(nodeid, "forward_r", {
		uid = uid,
		cmd = cmd,
		body = json.encode(body),
	})
	print("--------forward cmd", cmd, ack, ack and ack.cmd)
	if not ack then
		return nil
	end
	local body
	if ack.body then
		body = json.decode(ack.body)
	else
		body = {}
	end
	local ret_cmd = string.gsub(cmd, "_r$", "_a")
	respond(sock, ret_cmd, body)
	return body
end

M.close = clear
M.forward = forward
function M.start()
	cluster.watch_establish(establish)
	cluster.connect("role")
	cap = cluster.capacity["role"]
end

--------------gateway handlers----------------
---@param account string
---@param sid integer
---@return integer | nil
---@return integer
local function uid_of_server(account, sid)
	local dbk = dbk_uid[sid]
	local ok, uid = db.hget(dbk, account)
	if not ok then
		logger.error("[gateway] login_r account:", account, "sid", sid, "hget error", uid)
		return nil, code.internal_error
	end
	if not uid then -- 没有玩家ID, 尝试分配一个
		uid = db.newid()
		local ok, res = db.hsetnx(dbk, account, uid)
		if not ok then
			logger.error("[gateway] login_r account:", account, "sid", sid, "uid", uid, "hsetnx error", res)
			return nil, code.internal_error
		end
		if res ~= 1 then
			logger.error("[gateway] login_r account:", account,
				"sid", sid, "uid", uid, "hsetnx res", res)
			return nil, code.login_race
		end
	else
		uid = tonumber(uid)
		if not uid then
			logger.error("[gateway] login_r account:", account, "sid", sid, "uid", uid, "invalid uid")
			return nil, code.internal_error
		end
	end
	return uid, 0
end
function grouter.login_r(sock, cmd, req)
	local ok = logout(sock)
	if not ok then
		respond(sock, "login_a", code.internal_error)
	end
	local account = auth.account(sock)
	if not account then
		error(sock, "login_a", code.auth_first)
		logger.error("[gateway] login_r before auth")
		return false
	end
	local sid = req.server_id
	if not sid then
		error(sock, "login_a", code.args_invalid)
		logger.error("[gateway] login_r account:", account, "server_id is nil")
		return false
	end
	local uid, err = uid_of_server(account, sid)
	if not uid then
		error(sock, "login_a", err)
		return false
	end
	local os = uid_to_sock[uid]
	if os then
		clear(os)
		error(os, "kick_n", code.login_in_other)
		logger.error("[gateway] account:", account, "sid", sid, "uid", uid, "login in other")
	end
	local nodeid = assign_node(uid)
	local ack = cluster.call(nodeid, "forward_r", {
		uid = uid,
		cmd = cmd,
		body = json.encode(req),
	})
	local body = ack and json.decode(ack.body) or nil
	if not body then
		error(sock, "login_a", code.internal_error)
		logger.error("[gateway] login_r account:", account, "sid", sid, "uid", uid, "forward error", ack and ack.code)
		return false
	end
	if not body.code then
		login_success(uid, nodeid, sock)
	else
		logger.error("[gateway] login_r account:", account, "sid", sid, "uid", uid, "forward error", body.code)
	end
	respond(sock, "login_a", body)
	return ok
end

grouter.create_r = grouter.login_r

------------cluster handlers----------------
crouter.onlines_r = function(_, nodeid)
	local uids = {}
	for uid, _ in pairs(node_uid_set[nodeid]) do
		uids[#uids + 1] = uid
	end
	return {
		uids = uids,
	}
end

function crouter.multicast_n(req, nodeid)
	local body = proto:decode(req.cmd, req.body)
	print("[gateway] multicast_n", req.uids, req.cmd, body)
	for _, uid in pairs(req.uids) do
		local sock = uid_to_sock[uid]
		print("[gateway] multicast_n uid:", uid, type(sock))
		if sock then
			respond(sock, req.cmd, body)
		end
	end
end

function crouter.kick_r(body, nodeid)
	local uid = body.uid
	local sock = uid_to_sock[uid]
	if sock then
		clear(sock)
		error(sock, "kick_n", body.code)
	end
	return {}
end



return M

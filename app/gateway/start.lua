local core = require "core"
local logger = require "core.logger"
local websocket = require "core.websocket"
local args = require "lib.args"
local db = require "lib.db"
local cleanup = require "lib.cleanup"
local serverlist = require "lib.conf.serverlist"
local code = require "app.code"
local role = require "lib.agent.role"
local json = require "core.json"
local router = require "lib.router.gateway"

local pcall = core.pcall
local format = string.format
local tonumber = tonumber

local function respond(sock, cmd, obj)
	local dat = json.encode {
		cmd = cmd,
		body = obj
	}
	sock:write(dat)
end

local function error(sock, cmd, code_num)
	respond(sock, cmd, {code = code_num})
end

local dbk_uid = setmetatable({}, {__index = function(t, k)
	local dbk = format("uid:%d", k)
	t[k] = dbk
	return dbk
end})

local sock_to_account = {}
local uid_to_sock = {}
local sock_to_uid = {}

function router.auth_r(sock, _, req)
	local account = req.account
	local password = req.password
	if not account or not password then
		error(sock, "auth_a", code.args_invalid)
		logger.error("[gateway] account:", account, password "is invalid")
		return false
	end
	local ok, res = db.hget("account", account)
	if not ok then
		error(sock, "auth_a", code.internal_error)
		logger.error("[gateway] account:", account, "hsetnx error", res)
		return false
	else
		if not res then
			ok, res = db.hsetnx("account", account, password)
			if not ok then
				error(sock, "auth_a", code.internal_error)
				logger.error("[gateway] account:", account, "hsetnx error", res)
				return false
			end
			if res ~= 1 then
				error(sock, "auth_a", code.login_race)
				logger.error("[gateway] account:", account, "hsetnx res", res)
				return true
			end
		elseif res ~= password then
			error(sock, "auth_a", code.args_invalid)
			logger.error("[gateway] account:", account, "password:",
				password, "~=", res, "error")
			return false
		end
	end
	sock_to_account[sock] = account
	respond(sock, "auth_a", {})
	logger.info("[gateway] auth ok account:", account, password)
	return true
end

function router.login_r(sock, cmd, req)
	local account = sock_to_account[sock]
	if not account then
		error(sock, "login_a", code.auth_first)
		logger.error("[gateway] login_r before auth")
		return false
	end
	local sid = req.server_id
	if not sid then
		error(sock, "login_a", code.args_invalid)
		logger.error("[gateway] account:", account, "server_id is nil")
		return false
	end
	local dbk = dbk_uid[sid]
	local ok, uid = db.hget(dbk, account)
	if not ok then
		error(sock, "login_a", code.internal_error)
		logger.error("[gateway] account:", account, "sid", sid, "hget error", uid)
		return false
	end
	if not uid then	-- 没有玩家ID, 尝试分配一个
		uid = db.newid()
		local ok, res = db.hsetnx(dbk, account, uid)
		if not ok then
			error(sock, "login_a", code.internal_error)
			logger.error("[gateway] account:", account, "sid", sid, "uid", uid, "hsetnx error", res)
			return false
		end
		if res ~= 1 then
			error(sock, "login_a", code.login_race)
			logger.error("[gateway] account:", account, "sid", sid, "uid", uid, "hsetnx res", res)
			return true
		end
	else
		uid = tonumber(uid)
	end
	if not uid then
		error(sock, "login_a", code.internal_error)
		logger.error("[gateway] account:", account, "sid", sid, "uid", uid, "not number")
		return false
	end
	local os = uid_to_sock[uid]
	if os then
		uid_to_sock[uid] = nil
		sock_to_uid[os] = nil
		error(sock, "login_a", code.login_repeat)
		logger.error("[gateway] account:", account, "sid", sid, "uid", uid, "login repeat")
		return true
	end
	local fd = role.assign(uid)
	if not fd then
		error(sock, "login_a", code.internal_error)
		logger.error("[gateway] assign role of uid:", uid, "error")
		return false
	end
	uid_to_sock[uid] = sock
	sock_to_uid[sock] = uid
	local cmd, body = role.forward(uid, cmd, req)
	if not cmd then
		logger.error("[gateway] forward role of uid:", uid, "error")
		return false
	end
	respond(sock, cmd, body)
	return true
end

router.create_r = router.login_r

function router.servers_r(sock, _, _)
	local account = sock_to_account[sock]
	if not account then
		error(sock, "servers_a", code.auth_first)
		logger.error("[gateway] login_r before auth")
		return false
	end
	local list = serverlist.get()
	respond(sock, "servers_a", {list = list})
	logger.info("servers_a", json.encode(list))
	return true
end

local function process(sock)
	local dat, typ = sock:read()
	if not dat then
		return false
	end
	if typ == "close" then
		logger.info("[gateway] closed")
		return false
	end
	if typ ~= "text" or #dat < 4 then
		logger.error("[gateway] unknown type", typ)
		return false
	end
	local msg = json.decode(dat)
	if not msg then
		logger.error("[gateway] decode error", dat)
		return false
	end
	local cmd = msg.cmd
	local body = msg.body
	local uid = sock_to_uid[sock]
	if uid then
		cmd, body = role.forward(uid, cmd, body)
		if cmd then
			respond(sock, cmd, body)
		end
	else
		local fn = router[cmd]
		if not fn then
			logger.error("[gateway] invalid cmd", cmd)
			return false
		end
		local ok = fn(sock, cmd, body)
		if not ok then
			return false
		end
	end
	logger.info("[gateway] process cmd:", cmd, "ok")
	return true
end

local function handler(sock)
	while true do
		local ok, res = pcall(process, sock)
		if not ok then
			logger.error("[gateway] process error", res)
			break
		end
		if not res then
			break
		end
	end
	logger.info("[app.gateway] close sock:", sock)
	sock_to_account[sock] = nil
	local uid = sock_to_uid[sock]
	if uid then
		sock_to_uid[sock] = nil
		uid_to_sock[uid] = nil
	end
	sock:close()
end

local ok = websocket.listen {
	port = args.listen,
	handler = handler,
}
if not ok then
	cleanup()
end

local function kick_users(uid_set)
	for uid in pairs(uid_set) do
		local sock = uid_to_sock[uid]
		if sock then
			--kick_r
			sock:close()
		end
	end
end

role.start(kick_users)

logger.info("gateway start")

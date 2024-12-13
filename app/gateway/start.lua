local core = require "core"
local logger = require "core.logger"
local websocket = require "core.websocket"
local json = require "core.json"
local args = require "lib.args"
local cleanup = require "lib.cleanup"
local cluster = require "lib.cluster"
local serverlist = require "lib.conf.serverlist"
local code = require "app.code"
local router = require "app.router.gateway"
local crouter = require "app.router.cluster"
local role = require "app.gateway.role"
local auth = require "app.gateway.auth"
local utils = require "app.gateway.utils"

local pcall = core.pcall
local respond = utils.respond
local error = utils.error
local ackcmd = utils.ackcmd
function router.servers_r(sock, _, _)
	local list = serverlist.get()
	respond(sock, "servers_a", { list = list })
	logger.info("servers_a", json.encode(list))
	return true
end

local function process(sock)
	local dat, typ = sock:read()
	print("process", dat, ":", typ, "$")
	if not typ or typ == "close" then
		logger.info("[gateway] closed")
		return false
	end
	if typ == "ping" then
		sock:write(dat, "pong")
		return true
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
	if not auth.account(sock) then
		if cmd ~= "auth_r" then
			error(sock, ackcmd[cmd], code.auth_required)
			logger.error("[gateway] auth required")
			return true
		end
		auth.exec(sock, body)
		return true
	end
	local fn = router[cmd]
	if fn then
		return fn(sock, cmd, body)
	end
	role.forward(sock, cmd, body)
	logger.info("[gateway] process cmd:", cmd, "ok")
	return true
end

local function handler(sock)
	print("accept")
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
	auth.close(sock)
	role.close(sock)
	sock:close()
end

local ok = websocket.listen {
	port = args.listen,
	handler = handler,
}
if not ok then
	cleanup()
end
role.start()
cluster.serve(crouter)
logger.info("gateway start")

local json = require "core.json"
local websocket = require "core.websocket"
local logger = require "core.logger"
local packet = require "robot.packet"
local code = require "app.code"
local err = logger.error
logger.error = function(...)
	print(debug.traceback())
	err(...)
end

local sock, err = websocket.connect("http://127.0.0.1:10001")
if not sock then
	logger.error("connect error", err)
	return
end

local function request(cmd, body)
	local dat = packet.encode(cmd, body)
	local ok = sock:write(dat)
	if not ok then
		logger.error("write error")
		return
	end
	local dat, typ = sock:read()
	if typ ~= "binary" then
		logger.error("unknown type", typ)
		return
	end
	return (packet.decode(dat))
end

--认证
local ack = request("auth_r", {
	account = "foo",
	password = "123",
})
print("auth recv", json.encode(ack))


--登录
local ack = request("login_r", {
	server_id = 1,
})
print("login recv", json.encode(ack))

if ack and ack.code == code.user_not_exist then
	--创建角色
	local ack = request("create_r", {
		server_id = 1,
		name = "test1",
	})
	print("create recv", json.encode(ack))
end



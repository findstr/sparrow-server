local core = require "core"
local json = require "core.json"
local websocket = require "core.websocket"
local logger = require "core.logger"
local code = require "app.code"
local utils = require "robot.utils"
local assert = assert

local function auth(account, pwd, url)
	local sock, err = websocket.connect(url)
	if not sock then
		logger.error("connect error", err)
		return nil
	end
	--认证
	local ack = utils.request(sock, "auth_r", {
		account = account,
		password = pwd,
	})
	print("auth recv", json.encode(ack))
	assert(ack and not ack.code)
	--登录
	local ack = utils.request(sock, "login_r", {
		server_id = 1,
	})
	if ack and ack.code == code.user_not_exist then
		--创建角色
		ack = utils.request(sock, "create_r", {
			server_id = 1,
			name = account,
		})
		print("create recv", json.encode(ack))
	end
	print("login recv", json.encode(ack))
	assert(ack and not ack.code)
	return sock
end
local function case1()
	print("测试同一个gateway中相互挤号")
	local sock1 = auth("test1", "123", "http://127.0.0.1:10001")
	assert(sock1)
	print("first login `test1`")
	core.sleep(5000)
	local sock2 = auth("test1", "123", "http://127.0.0.1:10001")
	print("second login `test1`")
	local ack = utils.recv(sock1)
	print("first socket recv", json.encode(ack))
end

case1()

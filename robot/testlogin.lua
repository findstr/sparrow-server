local core = require "core"
local json = require "core.json"
local code = require "app.code"
local utils = require "robot.utils"
local assert = assert

local auth = utils.auth
local function case1()
	print("测试同一个gateway中相互挤号")
	local sock1 = auth("test1", "123", "http://127.0.0.1:10001")
	assert(sock1)
	print("first login `test1`")
	core.sleep(5000)
	local sock2 = auth("test1", "123", "http://127.0.0.1:10001")
	print("second login `test1`")
	local ack = utils.recv(sock1, nil)
	assert(ack and ack.code == code.login_in_other)
	print("first socket recv", json.encode(ack))
	print("case1 success")
end

case1()

print("test login all success")

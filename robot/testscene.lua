local core = require "core"
local logger = require "core.logger"
local json = require "core.json"
local waitgroup = require "core.sync.waitgroup"
local code = require "app.code"
local utils = require "robot.utils"
local assert = assert

local auth = utils.auth
local request = utils.request
local recv = utils.recv
local assert_not_nil = utils.assert_not_nil
local assert_success = utils.assert_success
local assert_equal = utils.assert_equal
local url = "http://127.0.0.1:10001"
local function case1()
	local sock1, uid, ack
	print("测试查看空场景")
	sock1, uid = auth("test1", "123", url)
	assert_not_nil(sock1, "登录")
	assert(sock1)
	assert(uid)

	ack = request(sock1, "scene_watch_r", {x = 0, z = 0})
	assert_success(ack, "拉取空场景")

	ack = request(sock1, "scene_put_r", {etype = 1, x = 0, z = 0})
	assert_success(ack, "放置小兵")

	ack = request(sock1, "scene_watch_r", {x = 0, z = 0})
	assert_success(ack, "拉取场景")
	assert_not_nil(ack.entities, "拉取小兵")
	assert_equal(#ack.entities, 1, "小兵数量")
	assert_equal(ack.entities[1].etype, 1, "小兵类型")
	assert_equal(ack.entities[1].x, 0, "小兵坐标")
	assert_equal(ack.entities[1].z, 0, "小兵坐标")
	assert_equal(ack.entities[1].uid, uid, "小兵uid")

	sock1:close()
end

local function case2()
	print("测试两个玩家同时放置小兵")
	local ack
	local sock1, uid1, sock2, uid2
	sock1, uid1 = auth("test1", "123", url)
	assert_not_nil(sock1, "登录")
	assert(sock1 and uid1)
	ack = request(sock1, "scene_watch_r", {})
	assert_success(ack, "test1 拉取场景")

	sock2, uid2 = auth("test2", "123", url)
	assert_not_nil(sock2, "登录")
	assert(sock2 and uid2)

	ack = request(sock2, "scene_watch_r", {})
	assert_success(ack, "test1 拉取场景")

	ack = request(sock1, "scene_put_r", {etype = 0, x = 0, z = 0})
	assert_success(ack, "test1 放置小兵")

	ack = request(sock2, "scene_put_r", {etype = 0, x = 0.8, z = 0.8})
	assert_success(ack, "test2 放置小兵")

	local wg = waitgroup:create()
	wg:fork(function()
		while true do
			local ackx = recv(sock1, nil)
			if not ackx then
				break
			end
			logger.info("test1 recv", json.encode(ackx))
		end
	end)
	wg:fork(function()
		while true do
			local ackx = recv(sock2, nil)
			if not ackx then
				break
			end
			logger.info("test2 recv", json.encode(ackx))
		end
	end)
	wg:wait()
end

--case1()
case2()
print("test scene all success")

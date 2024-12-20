local json = require "core.json"
local websocket = require "core.websocket"
local logger = require "core.logger"
local code = require "app.code"
local assert = assert

--- @param sock core.websocket.socket
local function send(sock, cmd, body)
	local dat = json.encode({
		cmd = cmd,
		body = body,
	})
	local ok = sock:write(dat, "text")
	if not ok then
		logger.error("write error")
	end
	return ok
end

--- @param sock core.websocket.socket
--- @param expect? string
local function recv(sock, expect)
	while true do
		local dat, typ = sock:read()
		if typ ~= "text" then
			logger.error("unknown type", typ)
			return nil
		end
		local msg = json.decode(dat)
		if not msg then
			logger.error("decode error", dat)
			return nil
		end
		local body = msg.body
		if body.code then
			body.status = code[body.code]
		end
		if not expect or msg.cmd == expect then
			return body
		end
		logger.info("recv", json.encode(msg))
	end
end

--- @param sock core.websocket.socket
--- @param cmd string
--- @param body table
--- @return table
local function request(sock, cmd, body)
	local ok = send(sock, cmd, body)
	if not ok then
		return { code = code.maintain }
	end
	return recv(sock, string.gsub(cmd, "_r$", "_a"))
end

--- @param account string
--- @param pwd string
--- @param url string
local function auth(account, pwd, url)
	local sock, err = websocket.connect(url)
	if not sock then
		logger.error("connect error", err)
		return nil, nil
	end
	--认证
	local ack = request(sock, "auth_r", {
		account = account,
		password = pwd,
	})
	print("auth recv", json.encode(ack))
	assert(ack and not ack.code)
	--登录
	local ack = request(sock, "login_r", {
		server_id = 1,
	})
	if ack and ack.code == code.user_not_exist then
		--创建角色
		ack = request(sock, "create_r", {
			server_id = 1,
			name = account,
		})
		print("create recv", json.encode(ack))
	end
	print("login recv", json.encode(ack))
	assert(ack and not ack.code)
	return sock, ack and ack.uid
end

local function assert_not_nil(v, msg)
	assert(v, msg)
	return v
end

local function assert_success(ack, msg)
	if ack then
		print(msg, json.encode(ack))
	end
	if ack and not ack.code == code.success then
		error(msg .. ":" .. ack and json.encode(ack) or "nil")
	end
end

local function assert_equal(a, b, msg)
	if a ~= b then
		error(msg .. ":" .. a .. "!=" .. b)
	end
end

local M = {
	request = request,
	send = send,
	recv = recv,
	auth = auth,
	assert_not_nil = assert_not_nil,
	assert_success = assert_success,
	assert_equal = assert_equal,
}

return M
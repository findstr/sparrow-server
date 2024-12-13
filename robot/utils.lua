local json = require "core.json"
local logger = require "core.logger"
local code = require "app.code"

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
local function recv(sock)
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
	return body
end

--- @param sock core.websocket.socket
local function request(sock, cmd, body)
	local ok = send(sock, cmd, body)
	if not ok then
		return nil
	end
	return recv(sock)
end

local M = {
	request = request,
	send = send,
	recv = recv,
}

return M
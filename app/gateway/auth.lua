local logger = require "core.logger"
local db = require "lib.db"
local code = require "app.code"
local utils = require "app.gateway.utils"

local sock_to_account = {}

local error = utils.error
local respond = utils.respond

local M = {}

function M.account(sock)
	return sock_to_account[sock]
end

function M.close(sock)
	sock_to_account[sock] = nil
end

function M.exec(sock, req)
	local account = req.account
	local password = req.password
	if not account or not password then
		error(sock, "auth_a", code.args_invalid)
		logger.error("[gateway] account:", account, password "is invalid")
		return
	end
	local ok, res = db.hget("account", account)
	if not ok then
		error(sock, "auth_a", code.internal_error)
		logger.error("[gateway] account:", account, "hsetnx error", res)
		return
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

return M
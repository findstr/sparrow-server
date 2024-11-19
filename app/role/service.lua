local json = require "core.json"
local logger = require "core.logger"
local crouter = require "lib.router.cluster"
local grouter = require "lib.router.gateway"
local cluster = require "lib.cluster"
function crouter.forward_r(req, fd)
	local cmd = req.cmd
	local body = json.decode(req.body)
	print("forward_r", cmd, req.body)
	local fn = grouter[cmd]
	if not fn then
		logger.error("[role] forward_r uid:", req.uid, "cmd:", cmd, "not found")
		return nil
	end
	local ack = fn(req.uid, body, fd)
	if ack then
		return { body = json.encode(ack) }
	end
	return nil
end

local online = require "app.role.online"
function crouter.multicast_n(req, fd)
	--TODO:
	print("multicast_n", req.cmd, req.uids)
	local gate_users = setmetatable({}, {
		__index = function(t, k)
			local v = {}
			t[k] = v
			return v
		end
	})
	for _, uid in pairs(req.uids) do
		local user = online[uid]
		print("[role] multicast_n uid:", uid, "user:", user)
		if user then
			local gatefd = user.gate
			if gatefd then
				local list = gate_users[gatefd]
				list[#list + 1] = uid
			end
		end
	end
	for gatefd, uids in pairs(gate_users) do
		print("[role] multicast_n gatefd:", gatefd, "uids:", uids)
		cluster.call(gatefd, "multicast_n", {
			uids = uids,
			cmd = req.cmd,
			body = req.body,
		})
	end
end


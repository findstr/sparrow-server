local logger = require "core.logger"
local node = require "lib.conf.node"
local cluster = require "lib.cluster"
local code = require "app.code"
local gr = require "app.router.gateway"

local scene_id = node.id("scene", 1)

local function forward(cmd)
	return function(uid, req)
		req.uid = uid
		req.lid = 0
		local ack, err = cluster.call(scene_id, cmd, req)
		if not ack then
			logger.error("[role] ", cmd, "uid:", uid, "err:", err)
			ack = { code = code.maintain }
		end
		return ack
	end
end

gr.scene_watch_r = forward("scene_watch_r")
gr.scene_unwatch_r = forward("scene_unwatch_r")
gr.scene_put_r = forward("scene_put_r")
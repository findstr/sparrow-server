local core = require "core"
local logger = require "core.logger"
local json = require "core.json"
local node = require "lib.conf.node"
local cluster = require "lib.cluster"
local callretp = require "app.proto.callret"
local clusterp = require "app.proto.cluster"
local gprint = print
print = function(...)
	local buf = {}
	local args = {...}
	for _, arg in ipairs(args) do
		if type(arg) == "table" then
			buf[#buf + 1] = json.encode(arg)
		else
			buf[#buf + 1] = arg and tostring(arg) or "nil"
		end
	end
	gprint(table.concat(buf, " "))
end

local args = require "lib.args"
local conf = require "lib.conf"
local db = require "lib.db"

local callret = callretp(clusterp)
local function unmarshal(typ, cmd, buf, size)
	if typ == "response" then
		cmd = callret[cmd]
	end
	return clusterp:decode(cmd, buf, size)
end

local function marshal(typ, cmd, body)
	if typ == "response" then
		if not body then
			return nil, nil
		end
		cmd = callret[cmd]
		if not cmd then
			return nil, nil, nil
		end
	end
	local cmdn = clusterp:tag(cmd)
	print("marshal", typ, cmd, body, cmdn)
	return cmdn, clusterp:encode(cmd, body, true)
end

conf.start()
db.start()
logger.setlevel(logger.DEBUG)
core.tracespan(node.selfid())
cluster.start(marshal, unmarshal)
dofile(string.format("app/%s/start.lua", args.service))
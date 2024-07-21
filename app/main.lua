local logger = require "core.logger"
local json = require "core.json"
local gprint = print
print = function(...)
	local buf = {}
	local args = {...}
	for _, arg in ipairs(args) do
		if type(arg) == "table" then
			buf[#buf + 1] = json.encode(arg)
		else
			buf[#buf + 1] = tostring(arg)
		end
	end
	gprint(table.concat(buf, " "))
end

local args = require "lib.args"
local conf = require "lib.conf"
local db = require "lib.db"

conf.start()
db.start()
logger.setlevel(logger.DEBUG)
dofile(string.format("app/%s/start.lua", args.service))
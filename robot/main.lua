local logger = require "core.logger"
local err = logger.error
logger.error = function(...)
	print(debug.traceback())
	err(...)
end

dofile("robot/testlogin.lua")
local core = require "core"
local assert = assert
local finalizers = {}
local function cleanup()
	for i = #finalizers, 1, -1 do
		finalizers[i]()
	end
	print("cleanup:", debug.traceback())
	core.exit(0)
end

core.signal("SIGINT", cleanup)

local M = {
	exec = cleanup,
	atexit = function(f)
		assert(f)
		finalizers[#finalizers + 1] = f
	end
}
return M

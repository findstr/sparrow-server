local core = require "core"
local function cleanup()
	print("------------", debug.traceback())
	core.exit(0)
end

core.signal("SIGINT", cleanup)

return cleanup

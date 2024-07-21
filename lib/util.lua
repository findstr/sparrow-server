local core = require "core"
local M = {}

function M.retry(n, fn)
	local res, err
	local timeout = 1000
	for i = 1, n do
		res, err = fn()
		if res then
			return res, "ok"
		end
		core.sleep(timeout)
		timeout = timeout * 2
	end
	return nil, err
end

return M
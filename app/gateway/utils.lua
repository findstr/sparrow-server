local json = require "core.json"
local function respond(sock, cmd, obj)
	local dat = json.encode {
		cmd = cmd,
		body = obj
	}
	local ok, err = sock:write(dat, "text")
	print("-----------respond", dat, ok, err)
end

local function error(sock, cmd, code_num)
	respond(sock, cmd, { code = code_num })
end

local ackcmd = setmetatable({}, {__index = function(t, k)
	local v = k:gsub("_r$", "_a")
	t[k] = v
	return v
end})

local M = {
	respond = respond,
	error = error,
	ackcmd = ackcmd,
}

return M

local proto = require "app.proto.cluster"
local assert = assert
local rawset = rawset

local mt = {
	__newindex = function(t, k, v)
		local id = assert(proto:tag(k), k)
		rawset(t, k, v)
		rawset(t, id, v)
	end
}

local M = setmetatable({}, mt)
return M
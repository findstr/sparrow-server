local pb = require "pb"
local protoc = require "protoc"
local p = protoc:new()
local function load_proto_file(file)
	local f = assert(io.open(file, "rb"))
	local data = f:read "*a"
	f:close()
	return data
end

assert(p:load(load_proto_file("proto/gateway.proto")))

local typemap = {}
local typeid = {}
local typeack = {}

for name in pairs(p.typemap) do
	if name:find("_[ra]$") then
		local name, basename, _ = pb.type(name)
		local id = assert(pb.enum("gateway.CMD", basename), basename)
		typemap[basename] = name
		typemap[id] = name
		typeid[basename] = id
		typeid[name] = id
		typeid[id] = id
		if name:find("_r$") then
			local ack_name = name:gsub("_r$", "_a")
			typeack[basename] = ack_name
			typeack[id] = ack_name
		end
	end
end
local M = {
	typemap = typemap,
	typeid = typeid,
	typeack = typeack,
}

return M
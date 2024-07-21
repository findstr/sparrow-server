local pb = require "pb"
local proto = require "app.proto.gateway"
local unpack = string.unpack
local pack = string.pack

local M = {}

function M.encode(cmd, body)
	local id = proto.typeid[cmd]
	local name = proto.typemap[cmd]
	print("encode", id, name)
	local dat = pb.encode(name, body)
	return pack("<I4", id) .. dat
end

function M.decode(buf)
	local cmd = unpack("<I4", buf)
	local name = proto.typemap[cmd]
	print("decode", cmd, name)
	local dat = buf:sub(5)
	return pb.decode(name, dat)
end

return M

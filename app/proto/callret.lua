local function callret(proto)
	local ret = {}
	for _, req_name, _ in proto:travel("struct") do
		if req_name:find("_r$") then
			local ack_name = req_name:gsub("_r$", "_a")
			local id = proto:tag(ack_name)
			if id then
				ret[req_name] = ack_name
				ret[proto:tag(req_name)] = ack_name
			end
		end
	end
	return ret
end


return callret
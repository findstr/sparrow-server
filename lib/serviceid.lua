local serviceid = {
	gateway = 1,
	role = 2,
	scene = 3,
}

local M = {}

function M.get(service)
	return serviceid[service]
end

function M.uuid(service, id)
	return serviceid[service] * 1000000 + id
end

return M
local code = require "lib.code"
local M = {
	args_invalid = 101,	--无效参数
	auth_fail = 102,	--认证失败
	auth_first = 103,	--请先认证
	user_exist = 105,	--用户已存在
	login_race = 107,	--两个地方同时登录
	login_in_other = 108,	--在其他地方登录
}

for k, v in pairs(code) do
	M[k] = v
end
for k, v in pairs(M) do
	code[v] = k
end

return M
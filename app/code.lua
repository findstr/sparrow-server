local M = {
	ok = 0,			--成功
	maintain = 1,		--服务器维护中
	internal_error = 2,	--内部错误
	login_others = 3,	--账号在其他地方登录
	user_not_exist = 4,	--玩家不存在
	user_name_repeated = 5,	--玩家名字重复


	args_invalid = 101,	--无效参数
	auth_fail = 102,	--认证失败
	auth_first = 103,	--请先认证
	user_exist = 105,	--用户已存在
	login_race = 107,	--两个地方同时登录
}

return M
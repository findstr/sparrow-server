local M = {
	ok = 0,			--成功
	maintain = 1,		--服务器维护中
	internal_error = 2,	--内部错误
	login_others = 3,	--账号在其他地方登录
	user_not_exist = 4,	--玩家不存在
	user_name_repeated = 5,	--玩家名字重复
}

return M
local libproto = require "lib.proto"
local zproto = require "zproto"
local proto = assert(zproto:parse([[
onlines_r 10000 {}
onlines_a 10001 {
	.uids:uint64[] 1
}
multicast_n 10002 {
	.uids:uint64[] 1
	.cmd:string 2
	.body:string 3
}

broadcast_n 10003 {
	.cmd:string 1
	.body:string 2
}

forward_r 20000 {
	.uid:uint64 1
	.cmd:string 2
	.body:string 3
}

forward_a 20001 {
	.cmd:string 1
	.body:string 2
}

kick_r 20003 {
	.uid:uint64 1
	.code:uint32 2
}

kick_a 20004 {
	.code:uint32 1
}

###########scene

scene_entity {
	.eid:int32 1		#小兵ID
	.etype:int32 2		#小兵兵种
	.uid:uint64 3		#玩家ID
	.lid:uint64 4		#玩家联盟ID
	.x:float 5		#坐标， 小兵当前坐标
	.z:float 6		#坐标， 小兵当前坐标
	.lifttime:uint32 7 	#小兵生命周期
}

scene_attack {
	.atk:int32 1	#攻击者小兵
	.def:int32 2	#被攻击者小兵
	.hurt:int32 3	#伤害值
	.defhp:int32 4	#被攻击者剩余血量
}

scene_watch_r 300000 {
	.uid:uint64 1
	.x:float 2
	.z:float 3
}

scene_watch_a 300001 {
	.entities:scene_entity[] 2
}

scene_unwatch_r 300002 {
	.uid:uint64 1
}

scene_unwatch_a 300003 {
}

scene_action_n 300004 {
	.nowms:uint64 1
	.entities:scene_entity[] 2
	.attacks:scene_attack[] 3
}

scene_put_r 300005 {
	.uid:uint64 1	#玩家ID
	.lid:uint64 2	#玩家联盟ID
	.etype:int32 3	#小兵兵种
	.x:float 4	#坐标
	.z:float 5	#坐标
}

scene_put_a 300006 { 	#放置小兵不需要主动返回, scene_action_n推送
	.code:uint32 1	#错误码
}


]] .. libproto))

return proto

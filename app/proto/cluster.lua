local zproto = require "zproto"

local proto = assert(zproto:parse [[
hello_r 10000 {
	.service:string 1
	.workerid:uint32 2
}

hello_a 10001 {}

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

scene_player {
	.uid:uint64 1
	.x:long 2
	.z:long 3
}

scene_enter_r 300000 {
	.uid:uint64 1
	.sid:uint64 2
	.x:long 3
	.z:long 4
}

scene_enter_a 300001 {
	.players:scene_player[] 2
}

scene_leave_r 300002 {
	.uid:uint64 1
}

scene_leave_a 300003 {}

scene_move_r 300004 {
	.uid:uint64 1
	.x:long 2
	.z:long 3
}

scene_move_a 300005 {
	.players:scene_player[] 2
}

scene_move_n 300006 {
	.uid:uint64 1
	.x:long 2
	.z:long 3
}

]])

return proto

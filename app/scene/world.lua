local core = require "core"
local logger = require "core.logger"
local time = require "core.time"
local logger = require "core.logger"
local libworld = require "lib.world"
local watch = require "app.scene.watch"
local router = require "app.router.cluster"

local world_entities = {}
local world_fighting = {}
local assert = assert
local pcall = core.pcall

local TICK_INTERVAL = 1000	--ms, 1s
local HP_INIT<const> = 1000
local LIFT_TIME<const> = 60000		--ms, 60s
local HIT_INTERVAL<const> = 1000	--ms, 1s

local world = libworld.new(time.now(), world_entities, world_fighting)
local function tick()
	local entities = {}
	local attacks = {}
	local nowms = time.now()
	world:tick(nowms)
	for eid, entity in pairs(world_entities) do
		if entity.lifttime <= nowms then
			entity.lifttime = nil		--清空生命周期
			world_fighting[eid] = nil	--清空战斗状态
			world:dead(eid)
		end
		entities[#entities + 1] = entity
	end
	for eid, entity in pairs(world_fighting) do
		local target_eid = entity.target
		local target = world_entities[target_eid]
		assert(target, entity.target)
		local atkms = entity.atkms or nowms
		if atkms <= nowms then
			entity.atkms = atkms + HIT_INTERVAL
			local hurt = 100
			local hp = target.hp
			if hp <= hurt then
				hp = 0
				world:dead(target_eid)
			else
				hp = hp - hurt
			end
			target.hp = hp
			attacks[#attacks + 1] = {
				atk = eid,
				def = target_eid,
				hurt = hurt,
				defhp = hp
			}
		end
	end
	if #entities > 0 or #attacks > 0 then
		watch.broadcast("scene_action_n", { entities = entities, attacks = attacks })
	end
end

function router.scene_watch_r(req, nodeid)
	watch.online(req.uid, nodeid)
	local entities = {}
	for _, entity in pairs(world_entities) do
		entities[#entities + 1] = entity
	end
	return {entities = entities}
end

function router.scene_unwatch_r(req, _)
	watch.offline(req.uid)
	return req
end

function router.scene_put_r(req, _)
	local eid = world:enter(req.uid, req.lid, req.x, req.z, req.etype)
	local entity = world_entities[eid]
	entity.hp = HP_INIT
	entity.lifttime = time.now() + LIFT_TIME
	watch.broadcast("scene_action_n", {entities = {entity}})
	return req
end

local timeout = core.timeout
local function safe_tick()
	local ok, err = pcall(tick)
	if not ok then
		logger.error("[scene] tick error:", err)
	end
	timeout(TICK_INTERVAL, safe_tick)
end
safe_tick()
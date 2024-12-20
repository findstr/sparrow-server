---@meta lib.world

---@class lib.world
local M = {}

---@param nowms integer
---@param entities table
---@param fighting table
---@return lib.world
M.new = function(nowms, entities, fighting)end

---@param world lib.world
---@param uid integer
---@param lid integer
---@param x number
---@param z number
---@param type integer
---@return integer
M.enter = function(world, uid, lid, x, z, type)end

---@param world lib.world
---@param eid integer
M.dead = function(world, eid)end

---@param world lib.world
---@param nowms integer
M.tick = function(world, nowms)end

---@param world lib.world
---@param alive integer[]
---@param free integer[]
---@return integer
M.dump = function(world, alive, free)end

return M
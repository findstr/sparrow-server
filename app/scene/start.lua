local logger = require "core.logger"
local args = require "lib.args"
local cluster = require "lib.cluster"
local router = require "app.router.cluster"


require "app.scene.world"

cluster.watch_establish(function (name, id, fd)
	logger.info("[scene] establish:", name, "id:", id, "fd:", fd)
end)

cluster.listen(args.listen)
cluster.serve(router)
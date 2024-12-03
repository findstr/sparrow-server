local logger = require "core.logger"
local args = require "lib.args"
local router = require "app.router.cluster"
local cluster = require "lib.cluster"

require "app.role.userm"
require "app.role.service"
cluster.watch_establish(function(name, id, fd)
        logger.info("role establish", name, id, fd)
end)
cluster.connect("scene")
logger.info("role start")
cluster.listen(args.listen)
--TODO: restore user onlines
cluster.serve(router)
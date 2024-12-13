local core = require "core"
local logger = require "core.logger"
local router = require "app.router.cluster"
local args = require "lib.args"
local cluster = require "lib.cluster"
local userm = require "app.role.userm"

require "app.role.service"

logger.info("role start")

cluster.watch_establish(function(name, id, fd)
        logger.info("role establish", name, id, fd)
end)
cluster.connect("scene")
cluster.listen(args.listen)
core.sleep(1000)
userm.restore()
cluster.serve(router)
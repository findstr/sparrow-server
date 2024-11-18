local logger = require "core.logger"
local args = require "lib.args"
local cluster = require "lib.cluster"

require "app.role.userm"
require "app.role.service"
cluster.connect("scene", function(name, id, fd)
        logger.info("scene connect", name, id, fd)
end)
logger.info("role start")
cluster.listen(args.listen, function(name, id, fd)
        logger.info("role establish to", name, id, fd)
end)
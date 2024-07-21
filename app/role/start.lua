local logger = require "core.logger"
local args = require "lib.args"
local cleanup = require "lib.cleanup"
local service = require "app.role.service"

require "app.role.userm"


local ok, err = service.listen(args.listen)
if not ok then
        logger.error("[role] listen addr:", args.listen, "error:", err)
        return cleanup()
end

logger.info("role start")
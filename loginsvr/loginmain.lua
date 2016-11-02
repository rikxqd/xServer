local skynet = require "skynet"
local cluster = require "cluster"
require "skynet.manager"

skynet.start(function()
    -- start logindb
    local db_instance = assert(tonumber(skynet.getenv("db_instance")))
    local logindb = skynet.newservice("mysqldb", "master", db_instance)
    -- start loginsvr
    local loginsvr = skynet.uniqueservice("loginsvr", logindb)
    skynet.name(".loginsvr", loginsvr)
    cluster.open("loginsvr")
    -- start logingate
    local login_port_from = assert(tonumber(skynet.getenv("login_port_from")))
    local login_port_to = assert(tonumber(skynet.getenv("login_port_to")))
    local conf = {
        address = assert(tostring(skynet.getenv("login_address"))),
        port = login_port_from,
        maxclient = assert(tonumber(skynet.getenv("maxclient"))),
        nodelay = not not (skynet.getenv("nodelay") == "true")
    }
    repeat
        local logingate = skynet.newservice("logingate", loginsvr)
        skynet.call(logingate, "lua", "open", conf)
        conf.port = conf.port + 1
    until(conf.port > login_port_to)
    skynet.exit()
end)
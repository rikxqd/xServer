local skynet = require "skynet"
local gateserver = require "snax.gateserver"
local socketdriver = require "socketdriver"
local netpack = require "netpack"
local crypt = require "crypt"

local gamesvr = assert(tonumber(...))
local connections = {}
local handler = {}
local CMD = {}

local function do_cleanup(fd)
    local conn = connections[fd]
    if conn then connections[fd] = nil end
end

local function do_dispatchmsg(conn, msg, sz)
    local msgdata = skynet.tostring(msg, sz)
    local ok = false;
    ok, msgdata = pcall(crypt.desdecode, conn.secret, msgdata)
    if not ok then skynet.error("Des decode error, fd: "..conn.fd) end
    ok, msgdata = pcall(crypt.base64decode(msgdata))
    if not ok then skynet.error("Base64 decode error: fd: ".. conn.fd) end
    skynet.send(gamesvr, "client", conn, msgdata)
end

local function do_verify(conn, msg, sz)
    local hmac = crypt.base64decode(netpack.tostring(msg, sz))
    local verify = crypt.hmac64(conn.challenge, conn.secret)
    if hmac ~= verify then
        skynet.error("Connection("..fd..") do verify error.")
        gateserver.closeclient(conn.fd)
    end
    conn.proc = do_login
end

local function do_auth(conn, msg, sz)
    if sz == 8192 then
        local cex = crypt.base64decode(netpack.tostring(msg, sz))
        local skey = crypt.randomkey()
        local sex = crypt.dhexchange(skey)
        conn.secret = crypt.dhsecret(cex, skey)
        socketdriver.send(conn.fd, netpack.pack(crypt.base64encode(sex)))
        conn.proc = do_verify
    else
        skynet.error("Connection("..conn.fd..") do auth error.")
        gateserver.closeclient(conn.fd)
    end
end

local function do_handshake(conn)
    conn.challenge = crypt.randomkey()
    socketdriver.send(conn.fd, netpack.pack(crypt.base64encode(conn.challenge)))
    conn.proc = do_auth
end

function handler.connect(fd, addr)
    local conn = {
        fd = fd,
        addr = addr,
        challenge = nil,
        secret = nil,
        proc = nil
    }
    connections[fd] = conn
    gateserver.openclient(fd)
    do_handshake(conn)
end

function handler.disconnect(fd)
    do_cleanup(fd)
end

function handler.error(fd, msg)
    skynet.error("Connection("..fd..") error: "..msg)
    gateserver.closeclient(fd)
end

function handler.message(fd, msg, sz)
    local conn = connections[fd]
    if conn then
        conn.proc(conn, msg, sz)
    else
        skynet.error("Unknown connection("..fd..").");
        gateserver.closeclient(fd)
    end
end

function handler.command(cmd, source, ...)
    local f = assert(CMD[cmd])
    return f(...)
end

function handler.warning(fd, size)
    skynet.error("Connection("..fd..") send buffer warning: high water marks !")
end

-- start a gatesvr service
gateserver.start(handler)
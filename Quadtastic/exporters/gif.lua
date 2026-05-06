local current_folder = ... and (...):match '(.-%.?)[^%.]+$' or ''
local libquadtastic = require("libquadtastic")
local common = require("common")
local utf8 = require("utf8")
local inspect = require(current_folder .. "lib.inspect")

local exporter = {}

exporter.name = "GIF"
exporter.ext = "gif"


function exporter.export(write, quads, info, ind)
    print(quads.animations)
end

function exporter.can_export(quads)
    return true 
end

return exporter

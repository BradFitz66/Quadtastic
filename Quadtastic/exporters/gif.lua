local libquadtastic = require("libquadtastic")
local common = require("common")
local Path = require("Path")
local gifwriter = require("lib.gif")
local exporter = {}
exporter.name = "GIF"
exporter.ext = "gif"
exporter.binary = true
exporter.multi_file = true

local function collect_frames(animation)
    local frames = {}
    for _, frame in common.det_pairs(animation.frames or animation.frames_compact or {}) do
        frames[#frames + 1] = {
            quad = frame.quad,
            duration = tonumber(frame.duration) or 16,
            flipX = animation.flipX,
            flipY = animation.flipY,
        }
    end
    return frames, animation.loop
end

local function valid_quad(quad)
    if not libquadtastic.is_quad(quad) then return false end
    for _, key in ipairs({"x", "y", "w", "h"}) do
        if quad[key] % 1 ~= 0 or quad[key] < 0 then return false end
    end
    return quad.w > 0 and quad.h > 0 and quad.w <= 65535 and quad.h <= 65535
end

function exporter.can_export(project, info)
    if type(project) ~= "table" then return false, "GIF export requires quad definitions." end
    local quads = project.quads or project
    if not quads._META or not quads._META.image_path then
        return false, "GIF export requires a source image."
    end
    local animations = project.animations or (info and info.animations) or {}
    if not next(animations) then return false, "GIF export requires at least one animation." end
    local names = {}
    for _, animation in common.det_pairs(animations) do
        local name = animation.name
        if type(name) ~= "string" or name == "" or name:find('[<>:"/\\|?*%c]')
           or name:find("[%. ]$") then
            return false, "Animation names must be valid filenames without path separators."
        end
        local stem = (name:match("^[^.]+") or name):upper()
        if stem == "CON" or stem == "PRN" or stem == "AUX" or stem == "NUL"
           or stem:match("^COM[1-9]$") or stem:match("^LPT[1-9]$") then
            return false, "Animation name is a reserved filename: " .. name
        end
        if names[name:lower()] then return false, "Duplicate animation filename: " .. name .. ".gif" end
        names[name:lower()] = true
        local frames = collect_frames(animation)
        if #frames == 0 then return false, "Animation has no frames to export: " .. name end
        for _, frame in ipairs(frames) do
            if not valid_quad(frame.quad) then
                return false, "GIF frames require non-negative integer coordinates and dimensions from 1 to 65535."
            end
            if frame.duration ~= frame.duration or frame.duration < 0 or frame.duration > 655350 then
                return false, "GIF frame durations must be between 0 and 655350 milliseconds."
            end
        end
    end
    return true
end

local function export_animation(write, animation, image)
    local frames, loop = collect_frames(animation)
    local width, height = 0, 0
    for _, frame in ipairs(frames) do
        local quad = frame.quad
        assert(quad.x + quad.w <= image:getWidth() and quad.y + quad.h <= image:getHeight(),
               "GIF frame lies outside the source image.")
        width, height = math.max(width, quad.w), math.max(height, quad.h)
    end
    local gif = gifwriter.new(nil, width, height)
    gif:begin(write, loop)
    for _, frame in ipairs(frames) do
        local quad = frame.quad
        local pixels = {
            getPixel = function(_, column, row)
                if column >= quad.w or row >= quad.h then return 0, 0, 0, 0 end
                local source_x = frame.flipX and quad.w - column - 1 or column
                local source_y = frame.flipY and quad.h - row - 1 or row
                return image:getPixel(quad.x + source_x, quad.y + source_y)
            end,
        }
        gif:write_frame(pixels, frame.duration)
    end
    gif:finish()
end

function exporter.export(write, project, info)
    local allowed, message = exporter.can_export(project, info)
    assert(allowed, message)
    assert(info and info.write_file, "GIF export requires multi-file output support.")
    local quads = project.quads or project
    local image_path = tostring(quads._META.image_path):gsub("\\", "/")
    if not Path.is_absolute_path(image_path) then
        image_path = tostring(Path(info.filepath:gsub("\\", "/")):parent() .. image_path)
    end
    local image = common.load_imagedata(image_path)
    local animations = project.animations or info.animations
    for _, animation in common.det_pairs(animations) do
        for _, frame in ipairs(collect_frames(animation)) do
            local quad = frame.quad
            assert(quad.x + quad.w <= image:getWidth() and quad.y + quad.h <= image:getHeight(),
                   "GIF frame lies outside the source image: " .. animation.name)
        end
    end
    for _, animation in common.det_pairs(animations) do
        info.write_file(animation.name .. ".gif", function(writer)
            export_animation(writer, animation, image)
        end)
    end
end

return exporter

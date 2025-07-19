--Load all .lua files in this directory

local path = ...
local function require_relative(p)
	return require(table.concat({path, p}, "."))
end
local quadimgui ={
    common        = require_relative("common"        ),
    imgui         = require_relative("imgui"         ),
    State         = require_relative("State"         ),
    Scrollpane    = require_relative("Scrollpane"    ),
    Frame         = require_relative("Frame"         ),
    Inputfield    = require_relative("Inputfield"    ),
    Tooltip       = require_relative("Tooltip"       ),
    Layout        = require_relative("Layout"        ),
    Button        = require_relative("Button"        ),
    LoadingAnim   = require_relative("LoadingAnim"   ),
    Label         = require_relative("Label"         ),
    Text          = require_relative("Text"          ),
    Window        = require_relative("Window"        ),
    Menu          = require_relative("Menu"          ),
    Dialog        = require_relative("Dialog"        ),
    Path          = require_relative("Path"          ),
    Version       = require_relative("Version"       ),
    strings       = require_relative("strings"       ),
    libquadtastic = require_relative("libquadtastic" ),
}


function quadimgui.init()
    local transform=require_relative("transform")()

    --Set love path to here
    love.filesystem.setIdentity(path)

    local workingDir = love.filesystem.getWorkingDirectory()
    print("Working directory: " .. workingDir)
  

    local med_font = love.graphics.newFont("res/m5x7.ttf", 16)
    med_font:setFilter("nearest", "nearest")
    local smol_font = love.graphics.newFont("res/m3x6.ttf", 16)
    smol_font:setFilter("nearest", "nearest")
    love.graphics.setFont(med_font)
  
    local stylesheet = love.graphics.newImage("res/style.png")
    local stylesheetData = love.image.newImageData("res/style.png")
  
    quadimgui.gui_state = quadimgui.imgui.init_state(transform)
    quadimgui.gui_state.style.small_font = smol_font
    quadimgui.gui_state.style.med_font = med_font
    quadimgui.gui_state.style.font = med_font
    quadimgui.gui_state.style.stylesheet = stylesheet
    quadimgui.gui_state.style.raw_quads = require_relative("res/style")
    quadimgui.gui_state.style.quads = quadimgui.libquadtastic.create_quads( quadimgui.gui_state.style.raw_quads,stylesheet:getWidth(), stylesheet:getHeight())
    quadimgui.gui_state.style.palette = quadimgui.libquadtastic.create_palette(quadimgui.gui_state.style.raw_quads.palette,stylesheet,stylesheetData)
    quadimgui.gui_state.style.font_color = quadimgui.gui_state.style.palette.shades.darkest

    quadimgui.gui_state.style.backgroundcanvas = love.graphics.newCanvas(2, 2)
    do
        -- Create a canvas with the background texture on it
        quadimgui.gui_state.style.backgroundcanvas:setWrap("repeat", "repeat")
            quadimgui.gui_state.style.backgroundcanvas:renderTo(function()
        love.graphics.draw(stylesheet, quadimgui.gui_state.style.quads.background)
        end)
    end

    quadimgui.gui_state.style.dashed_line = { horizontal = {}, vertical = {}, size = 8}
    do
        local line = quadimgui.gui_state.style.dashed_line.horizontal
        local size = quadimgui.gui_state.style.dashed_line.size
        line.canvas = love.graphics.newCanvas(size, 1)
        line.spritebatch = love.graphics.newSpriteBatch(line.canvas, 4096, "stream")
        line.canvas:setWrap("repeat", "repeat")
        line.canvas:renderTo(function()
        love.graphics.clear(0, 0, 0)
        love.graphics.rectangle("fill", 0, 0, size/2, 1)
        end)
    end

    do
        local line = quadimgui.gui_state.style.dashed_line.vertical
        local size = quadimgui.gui_state.style.dashed_line.size
        line.canvas = love.graphics.newCanvas(1, size)
        line.spritebatch = love.graphics.newSpriteBatch(line.canvas, 4096, "stream")
        line.canvas:setWrap("repeat", "repeat")
        line.canvas:renderTo(function()
        love.graphics.clear(0, 0, 0)
        love.graphics.rectangle("fill", 0, 0, 1, size/2)
        end)
    end

    quadimgui.gui_state.overlay_canvas = love.graphics.newCanvas(love.graphics.getWidth(), love.graphics.getHeight())
    quadimgui.gui_state.tooltip_canvas = love.graphics.newCanvas(love.graphics.getWidth(), love.graphics.getHeight())

    return quadimgui
end

return quadimgui.init()
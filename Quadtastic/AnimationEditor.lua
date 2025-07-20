local current_folder = ... and (...):match '(.-%.?)[^%.]+$' or ''
local Scrollpane = require(current_folder .. ".Scrollpane")
local imgui = require(current_folder .. ".imgui")
local Label = require(current_folder .. ".Label")
local Layout = require(current_folder .. ".Layout")
local Frame = require(current_folder .. ".Frame")
local AnimationEditor = {}

local grid_mesh

local function draw_elements(gui_state, state, elements)
    if state.animation_window_delta == nil then
        state.animation_window_delta = {x = 0, y = 0}
    end

    imgui.push_style(gui_state, "font", gui_state.style.small_font)
    for i = 1, 32 do
        local dx = state.animation_window_delta ~= nil and state.animation_window_delta.x + i * 32 or i * 32
        
        Label.draw(
            gui_state,
            dx,
            nil,
            64,
            12,
            i,
            { alignment_h = ":", alignment_v = ":" }
        )
        local r,g,b,a = love.graphics.getColor()
        love.graphics.setColor(r, g, b, 100)
        love.graphics.rectangle(
            "fill",
            (gui_state.layout.next_x + dx)+30,
            gui_state.layout.next_y,
            3,
            gui_state.layout.max_h
        )
        love.graphics.setColor(r, g, b, a)
    end
    imgui.pop_style(gui_state, "font")
    if(gui_state.input == nil or gui_state.input.mouse.buttons[2] == nil) then
        return
    end
    local mx, my = gui_state.transform:unproject(gui_state.input.mouse.x,
                                             gui_state.input.mouse.y)
    local quad = {
        x = gui_state.layout.next_x,
        y = gui_state.layout.next_y,
        w = gui_state.layout.max_w,
        h = gui_state.layout.max_h
    }
    local transform = gui_state.transform
    local in_x, in_y = mx >= quad.x and mx <= quad.x + quad.w,
                        my >= quad.y and my <= quad.y + quad.h

    local m1_down = gui_state.input.mouse.buttons[1].pressed
    local m2_down = gui_state.input.mouse.buttons[2].pressed

    local old_mouse_x = gui_state.input.mouse.old_x
    local old_mouse_y = gui_state.input.mouse.old_y
    local new_mouse_x = gui_state.input.mouse.x
    local new_mouse_y = gui_state.input.mouse.y

    local dx = new_mouse_x - old_mouse_x
    local dy = new_mouse_y - old_mouse_y
    if(m2_down and (in_x and in_y)) then
        if not old_mouse_x or not old_mouse_y or not new_mouse_x or not new_mouse_y then
            return
        end
        if dx ~= 0 or dy ~= 0 then
            state.animation_window_delta.x = state.animation_window_delta.x + dx
            state.animation_window_delta.y = state.animation_window_delta.y + dy
        end
    end
    if(my < -1 and my > -4 and in_x) then
        if(m1_down) then
            if(state.animation_window~=nil) then
                -- Drag-resize from the top
                local new_h = state.animation_window.h + dy
                state.animation_window.y = state.animation_window.y - dy*4
            end
        end
    end
end

AnimationEditor.draw = function(gui_state, state, x, y, w, h)
    if state.animation_window_delta==nil then
        state.animation_window_delta = {x = 0, y = 0}
    end
    do
        draw_elements(gui_state, state, state.quads)
    end
    if not (gui_state.input and gui_state.input.mouse) then
        return
    end
    
end



return AnimationEditor

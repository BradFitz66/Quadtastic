local current_folder = ... and (...):match '(.-%.?)[^%.]+$' or ''
local Scrollpane = require(current_folder .. ".Scrollpane")
local imgui = require(current_folder .. ".imgui")
local Label = require(current_folder .. ".Label")
local Layout = require(current_folder .. ".Layout")
local Inputfield = require(current_folder .. ".Inputfield")
local Button = require(current_folder .. ".Button")
local Tooltip = require(current_folder .. ".Tooltip")
local tableplus = require(current_folder .. ".tableplus")
print(current_folder)
local inspect = require("lib.inspect")
local AnimationEditor = {}


local function dict_length(dict)
    local count = 0
    for _ in pairs(dict) do
        count = count + 1
    end
    return count
end

local function draw_elements(gui_state, state, elements)
    if state.animation_window_delta == nil then
        state.animation_window_delta = {x = 0, y = 0}
    end
    if(state.animation_window == nil) then
        state.animation_window = {
            displayed_frame = 1,
            timer = 0,
        }
    end

    imgui.push_style(gui_state, "font", gui_state.style.small_font)
    --Calculate how many labels we can fit in the current window
    local selected_animation = state.animation_list ~= nil and state.animation_list.selected or nil
    local dx = -32
    for i = 1, 128 do
        dx = state.animation_window_delta ~= nil and state.animation_window_delta.x + i * 32 or i * 32
        do Layout.start(gui_state, dx)
            Label.draw(
                gui_state,
                nil,
                nil,
                32,
                12,
                i,
                { alignment_h = ":", alignment_v = ":" }
            )
            
            local frame = selected_animation and selected_animation.frames[i] or nil
            if(selected_animation~=nil) then
                if (frame) then
                    local quad = frame.quad
                    love.graphics.setColor(255, 255, 255, 255)
                    local x,y = quad.x, quad.y
                    local w,h = quad.w, quad.h
                    local ox, oy = quad.ox or 1, quad.oy or 1
                    love.graphics.draw(
                        state.image,
                        love.graphics.newQuad(
                            x,
                            y,
                            w,
                            h,
                            state.image:getWidth(),
                            state.image:getHeight()
                        ),
                        w,
                        gui_state.layout.next_y + 32,
                        0,
                        .5,
                        .5
                    )
                    frame.duration = Inputfield.draw(gui_state,0, 54, nil, nil, tostring(frame.duration),{filter = function(c)
                        return c:match("%d")
                    end})
                    Tooltip.draw(
                        gui_state,
                        "Duration of frame " .. i .. " in milliseconds",
                        gui_state.layout.next_x + 2,
                        gui_state.layout.next_y + 54
                    )
                end
                if (#state.selection:get_selection()==1) then
                    local pressed = Button.draw(
                        gui_state,
                        9,
                        72,
                        12,
                        12,
                        "",
                        frame and gui_state.style.quads.buttons.minus or gui_state.style.quads.buttons.plus,
                        { alignment_h = ":", alignment_v = ":", center_icon=true }
                    )
                    if pressed then
                        if(state.animation_list.selected ~= nil) then
                            if frame then
                                state.animation_list.selected.frames[i] = nil
                                
                            else
                                state.animation_list.selected.frames[i] = {
                                    quad = state.selection:get_selection()[1],
                                    duration = 1,
                                }
                            end
                            state.animation_list.selected.frames_compact = tableplus.compact(state.animation_list.selected.frames)
                        end 
                    end
                elseif (#state.selection:get_selection()~=1 and frame) then
                    local pressed = Button.draw(
                        gui_state,
                        9,
                        72,
                        12,
                        12,
                        "",
                        gui_state.style.quads.buttons.minus,
                        { alignment_h = ":", alignment_v = ":", center_icon=true }
                    )
                    if pressed then
                        if(state.animation_list.selected ~= nil) then
                            state.animation_list.selected.frames[i] = nil
                            state.animation_list.selected.frames_compact = tableplus.compact(state.animation_list.selected.frames)
                        end
                    end
                end
            end
        end Layout.finish(gui_state, "-")
        local r,g,b,a = love.graphics.getColor()
        love.graphics.setColor(255, 255, 255, 50)
        love.graphics.rectangle(
            "fill",
            (gui_state.layout.next_x + dx),
            gui_state.layout.next_y,
            1,
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
    if(state.animation_window_delta ~= nil) then
        if(state.animation_window_delta.x > -32) then
            state.animation_window_delta.x = -32
        elseif (state.animation_window_delta.x < -3576) then
            state.animation_window_delta.x = -3576
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
    if(state.playing_anim) then
        local selected_animation = state.animation_list and state.animation_list.selected or nil
        local frames = selected_animation~=nil and selected_animation.frames_compact or nil
        if(frames and #frames > 0) then
            if(selected_animation.displayed_frame > #frames) then
                selected_animation.displayed_frame = 1
            end
            local duration = frames[selected_animation.displayed_frame].duration/1000
            local len = dict_length(frames)
            state.animation_window.timer = state.animation_window.timer + love.timer.getDelta()
            if(state.animation_window.timer >= duration) then
                selected_animation.displayed_frame = selected_animation.displayed_frame + 1
                state.animation_window.timer = 0
                if(selected_animation.displayed_frame > len) then
                    selected_animation.displayed_frame = 1
                end
            end
        end
    end
end



return AnimationEditor

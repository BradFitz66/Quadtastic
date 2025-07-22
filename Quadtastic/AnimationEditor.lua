local current_folder = ... and (...):match '(.-%.?)[^%.]+$' or ''
local Scrollpane = require(current_folder .. ".Scrollpane")
local imgui = require(current_folder .. ".imgui")
local Label = require(current_folder .. ".Label")
local Layout = require(current_folder .. ".Layout")
local Inputfield = require(current_folder .. ".Inputfield")
local Button = require(current_folder .. ".Button")
local Tooltip = require(current_folder .. ".Tooltip")
local AnimationEditor = {}

local grid_mesh

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
            
            local anim = selected_animation and selected_animation.frames[i] or nil
            if(selected_animation~=nil) then
                if (anim) then
                    local quad = anim.quad
                    love.graphics.setColor(255, 255, 255, 255)
                    love.graphics.draw(
                        state.image,
                        love.graphics.newQuad(
                            quad.x,
                            quad.y,
                            quad.w,
                            quad.h,
                            state.image:getWidth(),
                            state.image:getHeight()
                        ),
                        nil,
                        gui_state.layout.next_y + 32,
                        0,
                        .5,
                        .5
                    )
                    anim.duration = Inputfield.draw(gui_state,0, 54, nil, nil, tostring(anim.duration),{filter = function(c)
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
                        anim and gui_state.style.quads.buttons.minus or gui_state.style.quads.buttons.plus,
                        { alignment_h = ":", alignment_v = ":", center_icon=true }
                    )
                    if pressed then
                        if(state.animation_list.selected ~= nil) then
                            if anim then
                                state.animation_list.selected.frames[i] = nil
                            else
                                state.animation_list.selected.frames[i] = {
                                    quad = state.selection:get_selection()[1],
                                    duration = 1,
                                }
                            end
                        end
                    end
                elseif (#state.selection:get_selection()~=1 and anim) then
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
        local anim = selected_animation and selected_animation.frames or nil
        if(anim and #anim > 0) then
            --Make sure displayed_frame is not higher than #anim
            if(state.animation_window.displayed_frame > #anim) then
                state.animation_window.displayed_frame = 1
            end
            local duration = anim[state.animation_window.displayed_frame].duration/1000
            local len = #anim
            state.animation_window.timer = state.animation_window.timer + love.timer.getDelta()
            if(state.animation_window.timer >= duration) then
                state.animation_window.displayed_frame = state.animation_window.displayed_frame + 1
                state.animation_window.timer = 0
                if(state.animation_window.displayed_frame > len) then
                    state.animation_window.displayed_frame = 1
                end
            end
        end
    end
end



return AnimationEditor

local current_folder = ... and (...):match '(.-%.?)[^%.]+$' or ''
local Frame = require(current_folder .. ".Frame")
local Layout = require(current_folder .. ".Layout")
local Text = require(current_folder .. ".Text")
local Scrollpane = require(current_folder .. ".Scrollpane")
local imgui = require(current_folder .. ".imgui")
local libquadtastic = require(current_folder .. ".libquadtastic")
local Button = require(current_folder .. ".Button")
local tableplus = require(current_folder .. ".tableplus")
local AnimationList = {}

local function draw_elements(gui_state, state, elements, last_hovered, quad_bounds)
    local clicked_element, hovered_element, double_clicked_element

    if(state.animation_list == nil) then
        state.animation_list = {}
        state.animation_list.last_action = nil
    end
    for i, element in pairs(elements) do
        local name = element.name or i
        local row_height = 16
        -- check if this quad will be visible, and only draw it if it is visible.
        local visible = gui_state.layout.next_y + row_height >= state.animation_scrollplane_state.y and
            gui_state.layout.next_y < state.animation_scrollplane_state.y +
            (state.animation_scrollplane_state.h or 0)

        local input_consumed
        local x, y
        local w, h
        if visible then
            local background_quads
            if  state.animation_list.selected == element then
                background_quads = gui_state.style.quads.rowbackground.selected
            elseif state.animation_list.hovered_element == element then
                background_quads = gui_state.style.quads.rowbackground.hovered
            else
                background_quads = gui_state.style.quads.rowbackground.default
            end

            love.graphics.setColor(255, 255, 255)
            -- Draw row background
            love.graphics.draw( -- top
                gui_state.style.stylesheet, background_quads.top, gui_state.layout.next_x, gui_state.layout.next_y, 0,
                gui_state.layout.max_w-24, 1)
            love.graphics.draw( -- center
                gui_state.style.stylesheet, background_quads.center, gui_state.layout.next_x,
                gui_state.layout.next_y + 2, 0, gui_state.layout.max_w-24, 12)
            love.graphics.draw( -- bottom
                gui_state.style.stylesheet, background_quads.bottom, gui_state.layout.next_x,
                gui_state.layout.next_y + 14, 0, gui_state.layout.max_w-24, 1)


            local delete_click = Button.draw(
                gui_state,
                gui_state.layout.next_x + gui_state.layout.max_w - 24,
                gui_state.layout.next_y,
                16,
                16,
                "",
                gui_state.style.quads.buttons.delete,
                { alignment_h = ":", alignment_v = ":", center_icon=true }
            )
            if delete_click then
                if(state.animation_list.selected == element) then
                    state.animation_list.selected = nil
                end
                print(elements[i].name)
                elements[i] = nil
                state.animation_list.last_action = "delete"
            end 
            Text.draw(gui_state, 8, nil, gui_state.layout.max_w, nil,
                string.format("%s", tostring(name)))
        end

        gui_state.layout.adv_x = gui_state.layout.max_w
        gui_state.layout.adv_y = row_height

        local x, y = gui_state.layout.next_x, gui_state.layout.next_y
        local w, h = gui_state.layout.adv_x-24, gui_state.layout.adv_y
        if not input_consumed and imgui.was_mouse_pressed(gui_state, x, y, w, h) then
            state.animation_list.selected = element
            if(state.animation_window) then
                state.animation_window.displayed_frame = 1
            end
            if gui_state.input.mouse.buttons[1].double_clicked then
                double_clicked_element = element
            end
        end
        if(imgui.is_mouse_in_rect(gui_state,x,y,w,h)) then
            hovered_element = element
            if not state.animation_list.hovered_element or state.animation_list.hovered_element ~= element then
                state.animation_list.hovered_element = element
            end
        elseif state.animation_list.hovered_element == element then
            state.animation_list.hovered_element = nil
            hovered_element = nil
        end



        -- Check if the mouse was clicked on this list entry
        Layout.next(gui_state, "|")
    end
    --Add a + button to add a new animation

    return clicked_element, hovered_element, double_clicked_element
end

local function dictionary_length(dict)
    local count = 0
    for _ in pairs(dict) do
        count = count + 1
    end
    return count
end

-- Draw the quads in the current state.
-- active is a table that contains for each quad whether it is active.
-- hovered is nil, or a single quad that the mouse hovers over.
AnimationList.draw = function(gui_state, state, x, y, w, h, last_hovered)
    -- The quad that the user clicked on
    local clicked
    local hovered
    local double_clicked
    local quad_bounds = {}
    if(state.animations == nil) then
        state.animations = {}
    end
    do Frame.start(gui_state, x, y, w, h)
        imgui.push_style(gui_state, "font", gui_state.style.small_font)
        imgui.push_style(gui_state, "font_color", gui_state.style.palette.shades.brightest)
        do state.animation_scrollplane_state = Scrollpane.start(gui_state, nil, nil, nil, nil, state.animation_scrollplane_state)
            do Layout.start(gui_state, nil, nil, nil, nil, {
                    noscissor = true
                })
                if state.image then
                    local animation_count = dictionary_length(state.animations)
                    clicked, hovered, double_clicked = draw_elements(gui_state, state, state.animations, last_hovered,quad_bounds)
                    local clicked,hovered, double_clicked = Button.draw(
                        gui_state,
                        animation_count>0 and 0 or -96,
                        animation_count*16,
                        12,
                        12,
                        "+"
                    )
                    if(clicked) then
                        local name = "New Animation " .. (#state.animations + 1)
                        table.insert(state.animations, {
                            name = name,
                            frames = {},
                            frames_compact = {}, --Same as frame, but without any empty frames
                            duration = 1,
                            displayed_frame = 1,
                            loop = true,
                            index = animation_count+1, 
                        })
                        print(#state.animations)
                        if(#state.animations == 0) then
                            state.animation_list.selected = state.animations[animation_count+1]
                        end
                    end
                end
            end Layout.finish(gui_state, "|")
            -- Restrict the viewport's position to the visible content as good as
            -- possible
            state.animation_scrollplane_state.min_x = 0
            state.animation_scrollplane_state.min_y = 0
            state.animation_scrollplane_state.max_x = gui_state.layout.adv_x
            state.animation_scrollplane_state.max_y = math.max(gui_state.layout.adv_y, gui_state.layout.max_h)
        end Scrollpane.finish(gui_state, state.animation_scrollplane_state)
        imgui.pop_style(gui_state, "font")
        imgui.pop_style(gui_state, "font_color")
    end Frame.finish(gui_state)

    -- Move viewport to focus quad if necessary
    if state.animation_scrollplane_state.focus_quad and quad_bounds[state.animation_scrollplane_state.focus_quad] then
        Scrollpane.move_into_view(state.animation_scrollplane_state, quad_bounds[state.animation_scrollplane_state.focus_quad])
        -- Clear focus quad
        state.animation_scrollplane_state.focus_quad = nil
    end

    return clicked, hovered, double_clicked
end

AnimationList.move_quad_into_view = function(scrollpane_state, quad)
    scrollpane_state.focus_quad = quad
end

return AnimationList

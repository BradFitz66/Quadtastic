local current_folder = ... and (...):match '(.-%.?)[^%.]+$' or ''
local Frame = require(current_folder .. ".Frame")
local Layout = require(current_folder .. ".Layout")
local Text = require(current_folder .. ".Text")
local Scrollpane = require(current_folder .. ".Scrollpane")
local imgui = require(current_folder .. ".imgui")
local tableplus = require(current_folder .. ".tableplus")
local Button = require(current_folder .. ".Button")
local AnimationList = {}

local function draw_elements(gui_state, state, elements, last_hovered, quad_bounds)
    local clicked_element, hovered_element, double_clicked_element

    if(state.animation_list == nil) then
        state.animation_list = {}
        state.animation_list.last_action = nil
    end

    local mouse_down = (gui_state.input ~= nil and gui_state.input.mouse ~= nil) and
        gui_state.input.mouse.buttons[1].pressed or false

    if mouse_down and state.animation_list.initial_click_x == nil then
        state.animation_list.initial_click_x = gui_state.input.mouse.x
        state.animation_list.initial_click_y = gui_state.input.mouse.y
    elseif not mouse_down then
        state.animation_list.initial_click_x = nil
        state.animation_list.initial_click_y = nil
        state.animation_list.drag_candidate = nil
    end

    local row_height = 16
    local list_start_y = gui_state.layout.next_y
    local list_start_x = gui_state.layout.next_x

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
                gui_state.layout.max_w-32, 1)
            love.graphics.draw( -- center
                gui_state.style.stylesheet, background_quads.center, gui_state.layout.next_x,
                gui_state.layout.next_y + 2, 0, gui_state.layout.max_w-32, 12)
            love.graphics.draw( -- bottom
                gui_state.style.stylesheet, background_quads.bottom, gui_state.layout.next_x,
                gui_state.layout.next_y + 14, 0, gui_state.layout.max_w-32, 1)

            local delete_click = Button.draw(
                gui_state,
                gui_state.layout.next_x + gui_state.layout.max_w - 32,
                gui_state.layout.next_y,
                16,
                16,
                "",
                gui_state.style.quads.buttons.delete,
                { alignment_h = ":", alignment_v = ":", center_icon=true }
            )
            local duplicate_click = Button.draw(
                gui_state,
                gui_state.layout.next_x + gui_state.layout.max_w - 16,
                gui_state.layout.next_y,
                16,
                16,
                "",
                gui_state.style.quads.menu.duplicate,
                { alignment_h = ":", alignment_v = ":", center_icon=true }
            )            
            if duplicate_click then
                local duplicate = {}

                duplicate.name = element.name .. " (copy)"
                duplicate.frames = {}
                duplicate.frames_compact = {}
                duplicate.duration = element.duration
                duplicate.displayed_frame = element.displayed_frame
                duplicate.loop = element.loop
                duplicate.flipped = element.flipped
                for j, frame in ipairs(element.frames) do
                    duplicate.frames[j] = {
                        quad = frame.quad,
                        duration = frame.duration,
                    }
                end
                duplicate.frames_compact = tableplus.compact(duplicate.frames)

                table.insert(elements, i+1, duplicate)

            end
            if delete_click then
                if(state.animation_list.selected == element) then
                    state.animation_list.selected = nil
                end
                elements[i] = nil
                state.animation_list.last_action = "delete"
            end 
            Text.draw(gui_state, 8, nil, gui_state.layout.max_w, nil,
                string.format("%s", tostring(name)))
        end

        gui_state.layout.adv_x = gui_state.layout.max_w
        gui_state.layout.adv_y = row_height
        local x, y = gui_state.layout.next_x, gui_state.layout.next_y
        local w, h = gui_state.layout.adv_x-32, gui_state.layout.adv_y
        if not input_consumed and imgui.was_mouse_pressed(gui_state, x, y, w, h) then
            state.animation_list.selected = element
            clicked_element = element
            state.animation_list.drag_candidate = element
            if(state.animation_window) then
                state.animation_window.displayed_frame = 1
            end
            if gui_state.input.mouse.buttons[1].double_clicked and state.animation_list.last_clicked_element == element then
                double_clicked_element = element
            end
            state.animation_list.last_clicked_element = element
        end
        if state.animation_list.drag_candidate == element and state.animation_list.dragging_element == nil and mouse_down then
            local dx = gui_state.input.mouse.x - (state.animation_list.initial_click_x or gui_state.input.mouse.x)
            local dy = gui_state.input.mouse.y - (state.animation_list.initial_click_y or gui_state.input.mouse.y)
            if math.abs(dx) > 5 or math.abs(dy) > 5 then
                state.animation_list.dragging_element = element
                state.animation_list.drag_candidate = nil
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

    -- Drag rendering and drop logic (runs once per frame, outside element loop)
    if state.animation_list.dragging_element ~= nil and gui_state.input ~= nil and gui_state.input.mouse ~= nil then
        local mx, my = gui_state.transform:unproject(gui_state.input.mouse.x, gui_state.input.mouse.y)
        local list_w = gui_state.layout.max_w - 32

        -- Draw ghost rectangle following the cursor
        love.graphics.setColor(255, 255, 255, 128)
        love.graphics.rectangle("fill", mx, my, 50, row_height)

        -- Find target insertion index and line position based on mouse y
        local n = #elements
        local target_index = n + 1
        local line_y = list_start_y + n * row_height
        for j = 1, n do
            if elements[j] ~= nil then
                local element_top = list_start_y + (j - 1) * row_height
                if my < element_top + row_height then
                    if my < element_top + row_height / 2 then
                        target_index = j
                        line_y = element_top
                    else
                        target_index = j + 1
                        line_y = element_top + row_height
                    end
                    break
                end
            end
        end

        -- Draw indicator line
        love.graphics.setColor(255, 255, 255, 200)
        love.graphics.rectangle("fill", list_start_x, line_y, list_w, 2)

        -- On mouse release, perform the reorder
        if not mouse_down then
            local dragging_index = nil
            for j = 1, n do
                if elements[j] == state.animation_list.dragging_element then
                    dragging_index = j
                    break
                end
            end
            if dragging_index ~= nil and target_index ~= dragging_index and target_index ~= dragging_index + 1 then
                table.insert(elements, target_index, table.remove(elements, dragging_index))
            end
            state.animation_list.dragging_element = nil
        end
    end

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
                            flipped = false,
                        })
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

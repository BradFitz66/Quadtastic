local current_folder = ... and (...):match '(.-%.?)[^%.]+$' or ''
local Scrollpane = require(current_folder .. ".Scrollpane")
local libquadtastic = require(current_folder .. ".libquadtastic")
local imgui = require(current_folder .. ".imgui")
local Rectangle = require(current_folder .. ".Rectangle")
local QuadList = require(current_folder .. ".QuadList")
local fun = require(current_folder .. ".fun")
local img_analysis = require(current_folder .. ".img_analysis")
local Grid = require(current_folder .. ".Grid")

local ImageEditor = {}

local grid_mesh

function ImageEditor.zoom(state, delta, mx, my)
    -- Ignore zoom instructions if no image is loaded
    if not state.image then
        return
    end

    if not state.display.zoom then
        state.display.zoom = 1
    end
    local cx, cy = Rectangle.center(state.scrollpane_state)
    cx, cy = cx / state.display.zoom, cy / state.display.zoom

    --Get difference between mouse position and center of the image
    local dx = mx - cx
    local dy = my - cy

    --Adjust the center of the image to the mouse position
    --Draw line to visualize difference
    -- love.graphics.setColor(255, 0, 0, 255)
    -- love.graphics.line(cx, cy, mx, my)


    local new_zoom
    if state.display.zoom <= 1 then
        if delta > 0 then
            new_zoom = state.display.zoom * 2
        elseif delta < 0 then
            new_zoom = state.display.zoom / 2
        else
            new_zoom = state.display.zoom
        end
    else
        new_zoom = math.floor(state.display.zoom + delta)
    end
    state.display.zoom = math.max(1 / 32, math.min(12, new_zoom))
    cx, cy = cx * state.display.zoom, cy * state.display.zoom
    -- cx = cx + (dx / 2)
    -- cy = cy + (dy / 2)

    Scrollpane.set_focus(state.scrollpane_state, {
        x = cx,
        y = cy
    }, "immediate")
end

local function iter_quads(tab, index, depth)
    if not depth then
        depth = 1
    end
    if not index then
        index = {}
    end
    if #index > depth then -- continue traversing nested element
        local keys, v = iter_quads(tab[index[depth]], index, depth + 1)
        if not keys then -- we have finished traversing that nested element
            -- Remove any deeper keys
            for i = depth + 1, #index do
                index[i] = nil
            end
            return iter_quads(tab, index, depth)
        else
            return keys, v
        end
    else -- Pick the next element on this level
        local next_key, next_value = next(tab, index[depth])
        if not next_key then
            return nil
        end -- we hit the end of this table
        index[depth] = next_key
        if libquadtastic.is_quad(next_value) then
            return index, next_value
        elseif type(next_value) == "table" then
            local nested_keys, nested_value = iter_quads(tab[next_key], index, depth + 1)
            if not nested_keys then -- we have finished traversing that nested element
                -- Remove any deeper keys
                for i = depth + 1, #index do
                    index[i] = nil
                end
                return iter_quads(tab, index, depth)
            else
                return nested_keys, nested_value
            end
        else -- we hit something that is neither a table nor a quad. Skip that
            return iter_quads(tab, index, depth)
        end
    end
end

local function draw_dashed_line(quad, gui_state, zoom)
    local t = gui_state.second
    local spritebatch_h = gui_state.style.dashed_line.horizontal.spritebatch
    local spritebatch_v = gui_state.style.dashed_line.vertical.spritebatch
    local size = gui_state.style.dashed_line.size
    local offset = 0
    local quad_top = love.graphics.newQuad(offset + t * size, 0, quad.w * zoom, 1, size, 1)
    offset = math.fmod(offset + quad.w * zoom, size)
    local quad_right = love.graphics.newQuad(0, offset + t * size, 1, quad.h * zoom, 1, size)
    offset = math.fmod(offset + quad.h * zoom, size)
    local quad_bottom = love.graphics.newQuad(offset + t * size, 0, quad.w * zoom, 1, size, 1)
    offset = math.fmod(offset + quad.w * zoom, size)
    local quad_left = love.graphics.newQuad(0, offset + t * size, 1, quad.h * zoom, 1, size)

    local x, y, w, h = quad.x, quad.y, quad.w, quad.h
    local d = .5 / zoom -- offset to center the line on the quad's border
    local s = 1 / zoom -- scale factor
    spritebatch_h:add(quad_top, x - d, y - d, 0, s, s)
    spritebatch_v:add(quad_right, x + w - d, y - d, 0, s, s)
    spritebatch_h:add(quad_bottom, x + w + d, y + h - d, 0, -s, s)
    spritebatch_v:add(quad_left, x - d, y + h + d, 0, s, -s)
end

local function show_quad(gui_state, state, quad, quadname)
    if libquadtastic.is_quad(quad) then
        -- If the mouse is inside that quad, display its name
        if gui_state.input and quadname and not state.hovered and not state.toolstate.selecting then
            if imgui.is_mouse_in_rect(gui_state, quad.x, quad.y, quad.w, quad.h) then
                gui_state.mousestring = quadname
                -- Set this quad as the hovered quad in the application state
                state.hovered = quad
            end
        end

        love.graphics.setColor(255, 255, 255, 255)

        love.graphics.push("all")
        love.graphics.setLineStyle("rough")
        love.graphics.setLineWidth(1 / state.display.zoom)
        if quad == state.hovered and (state.tool == "select" or state.tool == "create") or
            state.selection:is_selected(quad) then
            -- Use a dashed line to outline the quad
            love.graphics.setColor(255, 255, 255)
            draw_dashed_line(quad, gui_state, state.display.zoom)
            --[[
                Since we can't move multiple quad's origin at once, don't show any origin
                if there are multiple quads selected
            ]]
            if(#state.selection:get_selection()<=1) then
                local circle_x = quad.x + (quad.w * quad.ox)
                local circle_y = quad.y + (quad.h * quad.oy)
                love.graphics.draw(gui_state.style.stylesheet, gui_state.style.quads.tools.origin, circle_x - 3, circle_y - 3, 0, 1, 1)


                -- love.graphics.circle("fill", circle_x, circle_y, 2)
                -- love.graphics.setColor(0, 0, 0)
                -- love.graphics.circle("line", circle_x, circle_y, 2)
                -- love.graphics.setColor(255, 255, 255)
            end
        else
            -- Use a simple line to outline the quad
            love.graphics.rectangle("line", quad.x, quad.y, quad.w, quad.h)
        end
        love.graphics.pop()

    elseif type(quad) == "table" then
        -- If it's not a quad then it's a list of quads
        for k, v in pairs(quad) do
            local name = quadname and quadname .. "." .. tostring(k) or tostring(k)
            show_quad(gui_state, state, v, name)
        end
    end
end

local function get_dragged_rect(state, gui_state, img_w, img_h)
    assert(gui_state.input)
    -- Absolute mouse coordinates
    local mx, my = gui_state.input.mouse.x, gui_state.input.mouse.y
    local from_x = gui_state.input.mouse.buttons[1].at_x
    local from_y = gui_state.input.mouse.buttons[1].at_y
    -- Now check if the mouse coordinates were inside the scrollpane
    if Scrollpane.is_mouse_inside_widget(gui_state, state.scrollpane_state, mx, my) and
        Scrollpane.is_mouse_inside_widget(gui_state, state.scrollpane_state, from_x, from_y) then
        mx, my = gui_state.transform:unproject(mx, my)
        from_x, from_y = gui_state.transform:unproject(from_x, from_y)

        -- Restrict coordinates
        if img_w then
            mx = math.max(0, math.min(img_w - 1, mx))
            from_x = math.max(0, math.min(img_w - 1, from_x))
        end
        if img_h then
            my = math.max(0, math.min(img_h - 1, my))
            from_y = math.max(0, math.min(img_h - 1, from_y))
        end

        -- Round coordinates
        local rmx, rmy = math.floor(mx), math.floor(my)
        local rfx, rfy = math.floor(from_x), math.floor(from_y)

        local x = math.min(rmx, rfx)
        local y = math.min(rmy, rfy)
        local w = math.abs(rmx - rfx) + 1
        local h = math.abs(rmy - rfy) + 1

        return {
            x = x,
            y = y,
            w = w,
            h = h,
            ox = 0.5,
            oy = 0.5
        }
    else
        return nil
    end
end

local function should_snap_to_grid(gui_state, state)
    local should_snap = state.settings.grid.always_snap
    if imgui.are_exact_modifiers_pressed(gui_state, {"*alt"}) then
        -- invert should_snap
        should_snap = not should_snap
    end
    return should_snap
end

local function create_tool(app, gui_state, state, img_w, img_h)
    -- Draw a bright pixel where the mouse is
    love.graphics.setColor(255, 255, 255, 255)
    if gui_state.input then
        local mx, my = gui_state.transform:unproject(gui_state.input.mouse.x, gui_state.input.mouse.y)
        mx, my = math.floor(mx), math.floor(my)
        if should_snap_to_grid(gui_state, state) then
            mx, my = Grid.snap_point(state.settings.grid, mx, my)

            -- Update and draw grid mesh
            local cx, cy = Grid.cell_center(state.settings.grid, mx, my)
            grid_mesh:setVertex(1, mx, my, 0, 0, 255, 255, 255, 128)
            grid_mesh:setVertex(2, mx, my + 1, 0, 0, 255, 255, 255, 128)
            grid_mesh:setVertex(3, cx, my + 1, 0, 0, 255, 255, 255, 0)
            grid_mesh:setVertex(4, cx, my, 0, 0, 255, 255, 255, 0)
            love.graphics.draw(grid_mesh)
            grid_mesh:setVertex(1, mx, my, 0, 0, 255, 255, 255, 128)
            grid_mesh:setVertex(2, mx + 1, my, 0, 0, 255, 255, 255, 128)
            grid_mesh:setVertex(3, mx + 1, cy, 0, 0, 255, 255, 255, 0)
            grid_mesh:setVertex(4, mx, cy, 0, 0, 255, 255, 255, 0)
            love.graphics.draw(grid_mesh)
        end
        love.graphics.rectangle("fill", mx, my, 1, 1)
    end

    -- Draw a rectangle at the mouse's dragged area
    do
        if gui_state.input and gui_state.input.mouse.buttons[1] and gui_state.input.mouse.buttons[1].pressed then
            local rect = get_dragged_rect(state, gui_state, img_w, img_h)
            if rect then
                if should_snap_to_grid(gui_state, state) then
                    rect = Grid.snap_rect(state.settings.grid, rect)
                end
                show_quad(gui_state, state, rect)
                gui_state.mousestring = string.format("%dx%d", rect.w, rect.h)
            end
        end
    end

    -- If the mouse was dragged and released in this scrollpane then add a
    -- new quad
    do
        -- Check if the lmb was released
        if gui_state.input and gui_state.input.mouse.buttons[1] and gui_state.input.mouse.buttons[1].releases > 0 then
            local rect = get_dragged_rect(state, gui_state, img_w, img_h)
            if rect then
                if should_snap_to_grid(gui_state, state) then
                    rect = Grid.snap_rect(state.settings.grid, rect)
                end

                if rect.w > 0 and rect.h > 0 then
                    app.quadtastic.create(rect)
                end
            end
        end
    end
end

local function wand_tool(app, gui_state, state)
    if gui_state.input then
        -- Draw a bright pixel where the mouse is
        love.graphics.setColor(255, 255, 255, 255)
        local mx, my = gui_state.transform:unproject(gui_state.input.mouse.x, gui_state.input.mouse.y)
        mx, my = math.floor(mx), math.floor(my)
        love.graphics.rectangle("fill", mx, my, 1, 1)
        -- If a rectangle larger than 1px is dragged, scan the dragged
        local rect
        if gui_state.input.mouse.buttons[1] and
            (gui_state.input.mouse.buttons[1].pressed or gui_state.input.mouse.buttons[1].releases >= 1) then
            local img_w, img_h = state.image:getDimensions()
            rect = get_dragged_rect(state, gui_state, img_w, img_h)
        end

        if rect and rect.w > 1 and rect.h > 1 then
            show_quad(gui_state, state, rect)
            local rects = img_analysis.enclosed_chunks(state.image, rect.x, rect.y, rect.w, rect.h)

            if should_snap_to_grid(gui_state, state) then
                -- First expand all new quads so that they occupy complete grid cells
                for i in ipairs(rects) do
                    -- Expand rect to tile size
                    rects[i] = Grid.expand_rect(state.settings.grid, rects[i])
                end

                -- Now remove duplicates.
                -- TODO: This is slow. Could be faster when quads are sorted
                local remaining = {}
                for _, r in ipairs(rects) do
                    local is_new = true
                    for _, existing in ipairs(remaining) do
                        -- Compare r to the existing rectangle
                        if r.x == existing.x and r.y == existing.y and r.w == existing.w and r.h == existing.h then
                            is_new = false
                            break
                        end
                    end
                    if is_new then
                        table.insert(remaining, r)
                    end
                end
                rects = remaining
            end

            for i in ipairs(rects) do
                draw_dashed_line(rects[i], gui_state, state.display.zoom)
            end
            gui_state.mousestring = string.format("%d quads", #rects)
            if not gui_state.input.mouse.buttons[1].pressed and #rects > 0 then
                app.quadtastic.create(rects)
            end
        else
            -- Find strip of opaque pixels
            local quad = img_analysis.outter_bounding_box(state.image, mx, my)
            if quad and should_snap_to_grid(gui_state, state) then
                quad = Grid.expand_rect(state.settings.grid, quad)
            end
            if quad then
                draw_dashed_line(quad, gui_state, state.display.zoom)
                gui_state.mousestring = string.format("%dx%d", quad.w, quad.h)
                if gui_state.input.mouse.buttons[1] and gui_state.input.mouse.buttons[1].presses >= 1 then
                    app.quadtastic.create(quad)
                end
            end
        end
    end
end

local function palette_tool(app, gui_state, state)
    if gui_state.input then
        -- Draw a bright pixel where the mouse is
        love.graphics.setColor(255, 255, 255, 255)
        local mx, my = gui_state.transform:unproject(gui_state.input.mouse.x, gui_state.input.mouse.y)
        mx, my = math.floor(mx), math.floor(my)
        love.graphics.rectangle("fill", mx, my, 1, 1)
        -- If a rectangle larger than 1px is dragged, scan the dragged
        local rect
        if gui_state.input.mouse.buttons[1] and
            (gui_state.input.mouse.buttons[1].pressed or gui_state.input.mouse.buttons[1].releases >= 1) then
            local img_w, img_h = state.image:getDimensions()
            rect = get_dragged_rect(state, gui_state, img_w, img_h)
        end

        if rect and rect.w > 0 and rect.h > 0 then
            show_quad(gui_state, state, rect)
            local rects = img_analysis.palette(state.image, rect.x, rect.y, rect.w, rect.h)
            for _, r in ipairs(rects) do
                draw_dashed_line(r, gui_state, state.display.zoom)
            end
            gui_state.mousestring = string.format("%d quads", #rects)
            if not gui_state.input.mouse.buttons[1].pressed and #rects > 0 then
                app.quadtastic.create(rects)
            end
        end
    end
end

local function select_tool(app, gui_state, state, img_w, img_h)
    -- Check if we should start resizing a quad
    local direction

    local function get_cursor_string(dir)
        local cursor_string
        if dir.n and dir.e or dir.s and dir.w then
            cursor_string = "sizenesw"
        elseif dir.n and dir.w or dir.s and dir.e then
            cursor_string = "sizenwse"
        elseif dir.n or dir.s then
            cursor_string = "sizens"
        elseif dir.w or dir.e then
            cursor_string = "sizewe"
        end
        return cursor_string
    end

    if not state.toolstate.mode then
        local mx, my = gui_state.input.mouse.x, gui_state.input.mouse.y
        mx, my = gui_state.transform:unproject(mx, my)

        -- Returns the directions in which a quad should be resized based on where
        -- the mouse was pressed
        local function get_resize_directions(quad)
            -- Make a rough check to see if the mouse is near any edge
            if mx < quad.x - 1 or mx > quad.x + quad.w + 1 or my < quad.y - 1 or my > quad.y + quad.h + 1 then
                return nil
            end

            local border = 2 / state.display.zoom
            local dir = {}

            if math.abs(mx - quad.x) <= border then
                dir.w = true
            elseif math.abs(mx - (quad.x + quad.w)) <= border then
                dir.e = true
            end
            if math.abs(my - quad.y) <= border then
                dir.n = true
            elseif math.abs(my - (quad.y + quad.h)) <= border then
                dir.s = true
            end
            if not (dir.n or dir.e or dir.s or dir.w) then
                return nil
            else
                return dir
            end
        end

        -- Check if the mouse was pressed on the border of a selected quad
        if state.hovered and libquadtastic.is_quad(state.hovered) and state.selection:is_selected(state.hovered) then
            direction = get_resize_directions(state.hovered)
        else -- check each selected quad
            for _, quad in pairs(state.selection:get_selection()) do
                if libquadtastic.is_quad(quad) then
                    direction = get_resize_directions(quad)
                    if direction then
                        break
                    end
                end
            end
        end
        if direction then
            if gui_state.input.mouse.buttons[1] and gui_state.input.mouse.buttons[1].presses >= 1 then
                state.toolstate.mode = "resizing"
                state.toolstate.direction = direction

                -- Store the initial size of each quad
                state.toolstate.original_quad = {}
                for i, v in ipairs(state.selection:get_selection()) do
                    if libquadtastic.is_quad(v) then
                        local mx, my = gui_state.input.mouse.x, gui_state.input.mouse.y
                        mx, my = gui_state.transform:unproject(mx, my)

                        state.toolstate.original_quad[i] = {
                            x = v.x,
                            y = v.y,
                            w = v.w,
                            h = v.h,
                            ox = v.ox,
                            oy = v.oy
                        }
                    end
                end
            end

            -- Set the cursor
            love.mouse.setCursor(gui_state.style.cursors[get_cursor_string(direction)])
        end

    end

    local f = fun.partial(imgui.is_key_pressed, gui_state)
    if state.hovered and not state.toolstate.mode and not direction then
        -- If the hovered quad is already selected, show the movement cursor, and
        -- move the quads when the mouse is dragged
        if state.selection:is_selected(state.hovered) then
            if gui_state.input.mouse.buttons[1] and gui_state.input.mouse.buttons[1].presses >= 1 then
                state.toolstate.original_pos = {}
                --Don't want the ability to move multiple quad's origin at once 
                --Might cause weird behaviour especially if the quads are different sizes
                if(#state.selection:get_selection()==1) then
                    for i, v in ipairs(state.selection:get_selection()) do
                        if libquadtastic.is_quad(v) then
                        if(v.ox and v.oy) then
                                --ox is the relative x coordinate of the origin
                                --oy is the relative y coordinate of the origin
                            
                                local ox = v.x + v.ox * v.w
                                local oy = v.y + v.oy * v.h
                                --Check if mouse is touching the origin (within 4 pixels)
                                local mx, my = gui_state.input.mouse.x, gui_state.input.mouse.y
                                mx, my = gui_state.transform:unproject(mx, my)
                                if(math.abs(mx - ox) <= 4 and math.abs(my - oy) <= 4) then
                                    state.toolstate.mode = "moving_origin"
                                    state.toolstate.original_pos = {}
                                    for i, v in ipairs(state.selection:get_selection()) do
                                        if libquadtastic.is_quad(v) then
                                            state.toolstate.original_pos[i] = {
                                                x = v.ox* v.w,
                                                y = v.oy* v.h,
                                                ox = v.ox,
                                                oy = v.oy
                                            }
                                        end
                                    end
                                    break
                                else
                                    state.toolstate.mode = "dragging"
                                    -- Save the locations of all quads
                                    for i, v in ipairs(state.selection:get_selection()) do
                                        if libquadtastic.is_quad(v) then
                                            state.toolstate.original_pos[i] = {
                                                x = v.x,
                                                y = v.y
                                            }
                                        end
                                    end              
                                end                    
                            end
                        end
                    end
                else
                    state.toolstate.mode = "dragging"
                    -- Save the locations of all quads
                    for i, v in ipairs(state.selection:get_selection()) do
                        if libquadtastic.is_quad(v) then
                            state.toolstate.original_pos[i] = {
                                x = v.x,
                                y = v.y
                            }
                        end
                    end              
                end
            else
                love.mouse.setCursor(gui_state.style.cursors.hand_cursor)
            end
            -- Else select it on click
        elseif imgui.was_mouse_released(gui_state, state.hovered.x, state.hovered.y, state.hovered.w, state.hovered.h) then
            -- Change selection depending on modifiers
            -- If neither shift or ctrl is pressed, clear the selection
            if fun.any(f, {"lshift", "rshift", "lctrl", "rctrl"}) then
                state.selection:select({state.hovered})
            else
                state.selection:set_selection({state.hovered})
            end
            QuadList.move_quad_into_view(state.quad_scrollpane_state, state.hovered)
        end

        -- The mouse is not hovering over any quads. Check if we should draw a
        -- selection box
    elseif gui_state.input.mouse.buttons[1] and gui_state.input.mouse.buttons[1].pressed and
        (not state.toolstate.mode or state.toolstate.mode == "selecting") then
            
        --Determine if mouse is over origin.

        --We do this here in cases where the origin may be outside of the bounding box of the quad
        --If we didn't do this, we would just end up deselecting the quad when attempting to move the origin and thus make it impossible to change
        if(#state.selection:get_selection()==1) then
            for i, v in ipairs(state.selection:get_selection()) do
                if libquadtastic.is_quad(v) then
                if(v.ox and v.oy) then
                        --ox is the relative x coordinate of the origin
                        --oy is the relative y coordinate of the origin
                    
                        local ox = v.x + v.ox * v.w
                        local oy = v.y + v.oy * v.h
                        --Check if mouse is touching the origin (within 4 pixels)
                        local mx, my = gui_state.input.mouse.x, gui_state.input.mouse.y
                        mx, my = gui_state.transform:unproject(mx, my)
                        if(math.abs(mx - ox) <= 4 and math.abs(my - oy) <= 4) then
                            state.toolstate.mode = "moving_origin"
                            state.toolstate.original_pos = {}
                            for i, v in ipairs(state.selection:get_selection()) do
                                if libquadtastic.is_quad(v) then
                                    state.toolstate.original_pos[i] = {
                                        x = v.ox* v.w,
                                        y = v.oy* v.h,
                                        ox = v.ox,
                                        oy = v.oy
                                    }
                                end
                            end
                            break
                        else
                            state.toolstate.mode = "dragging"
                            -- Save the locations of all quads
                            for i, v in ipairs(state.selection:get_selection()) do
                                if libquadtastic.is_quad(v) and state.toolstate.original_pos ~= nil then
                                    if i < #state.toolstate.original_pos then
                                        state.toolstate.original_pos[i] = {
                                            x = v.x,
                                            y = v.y
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        if state.toolstate.mode == "moving_origin" then
            return
        end

        -- If neither shift or ctrl is pressed, clear the selection
        if not fun.any(f, {"lshift", "rshift", "lctrl", "rctrl"}) then
            state.selection:clear_selection()
        end
        state.toolstate.mode = "selecting"

        local rect = get_dragged_rect(state, gui_state)

        -- If the mouse button was pressed outside the image editor, then there is
        -- no dragged rectangle.
        if rect then
            love.graphics.setColor(255, 255, 255, 255)
            draw_dashed_line(rect, gui_state, state.display.zoom)

            -- Highlight all quads that are enclosed in the dragged rect
            local keys, quad = iter_quads(state.quads)
            love.graphics.setColor(gui_state.style.palette.shades.bright(128))
            while keys do
                if Rectangle.contains(rect, quad.x, quad.y, quad.w, quad.h) then
                    love.graphics.rectangle("fill", quad.x, quad.y, quad.w, quad.h)
                end
                keys, quad = iter_quads(state.quads, keys)
            end
        end
    end

    if not (gui_state.input.mouse.buttons[1] and gui_state.input.mouse.buttons[1].pressed) then
        if state.toolstate.mode == "selecting" then
            -- Add all quads to the selection that are enclosed in the dragged rect
            local rect = get_dragged_rect(state, gui_state)

            -- If the mouse button was pressed outside the image editor, then there is
            -- no dragged rectangle.
            if rect then
                local keys, quad = iter_quads(state.quads)
                while keys do
                    if Rectangle.contains(rect, quad.x, quad.y, quad.w, quad.h) then
                        state.selection:select({quad})
                    end
                    keys, quad = iter_quads(state.quads, keys)
                end
            end

        elseif state.toolstate.mode == "dragging" then
            app.quadtastic.commit_movement(state.selection:get_selection(), state.toolstate.original_pos)
        elseif state.toolstate.mode == "resizing" then
            app.quadtastic.commit_resizing(state.selection:get_selection(), state.toolstate.original_quad)
        elseif state.toolstate.mode == "moving_origin" then
            app.quadtastic.commit_origin_movement(state.selection:get_selection(), state.toolstate.original_pos)
        end
        state.toolstate.mode = nil
    end

    -- dragged movement in sprite pixels
    local dpx, dpy = 0, 0
    if gui_state.input.mouse.buttons[1] then
        local acc_dx = gui_state.input.mouse.x - gui_state.input.mouse.buttons[1].at_x
        local acc_dy = gui_state.input.mouse.y - gui_state.input.mouse.buttons[1].at_y
        acc_dx, acc_dy = gui_state.transform:unproject_dimensions(acc_dx, acc_dy)
        dpx = math.modf(acc_dx)
        dpy = math.modf(acc_dy)
    end

    if state.toolstate.mode == "dragging" then

        love.mouse.setCursor(gui_state.style.cursors.move_cursor)
        -- Move the quads by the dragged amount
        app.quadtastic.move_quads(state.selection:get_selection(), state.toolstate.original_pos, dpx, dpy, img_w, img_h,
            should_snap_to_grid(gui_state, state))
    elseif state.toolstate.mode == "resizing" then
        love.mouse.setCursor(gui_state.style.cursors[get_cursor_string(state.toolstate.direction)])
        app.quadtastic.resize_quads(state.selection:get_selection(), state.toolstate.original_quad,
            state.toolstate.direction, dpx, dpy, img_w, img_h, should_snap_to_grid(gui_state, state))
    end

    if(state.toolstate.mode == "moving_origin") then
        love.mouse.setCursor(gui_state.style.cursors.move_cursor)
        app.quadtastic.move_origin(state.selection:get_selection(), state.toolstate.original_pos, dpx, dpy, img_w, img_h,
            should_snap_to_grid(gui_state, state))
    end

end

local function handle_input(app, gui_state, state, img_w, img_h)
    if state.tool == "create" then
        create_tool(app, gui_state, state, img_w, img_h)
    elseif state.tool == "select" then
        select_tool(app, gui_state, state, img_w, img_h)
    elseif state.tool == "wand" then
        wand_tool(app, gui_state, state, img_w, img_h)
    elseif state.tool == "palette" then
        palette_tool(app, gui_state, state, img_w, img_h)
    end

    -- If the middle mouse button was dragged in this scrollpane, pan the image
    -- by the dragged distance
    if gui_state.input and gui_state.input.mouse.buttons[2] and gui_state.input.mouse.buttons[2].pressed then
        local button_state = gui_state.input.mouse.buttons[2]
        if Scrollpane.is_mouse_inside_widget(gui_state, state.scrollpane_state, button_state.at_x, button_state.at_y) then
            local dx, dy = -gui_state.input.mouse.dx, -gui_state.input.mouse.dy
            dx, dy = gui_state.transform:unproject_dimensions(dx, dy)
            dx, dy = dx * state.display.zoom, dy * state.display.zoom
            Scrollpane.move_viewport(state.scrollpane_state, dx, dy)
        end
    end

    -- if CTRL was pressed and the mousewheel was moved, adjust the zoom level
    -- and consume the mousewheel movement
    if gui_state.input and gui_state.input.mouse.wheel_dy and
        (imgui.is_key_pressed(gui_state, "lctrl") or imgui.is_key_pressed(gui_state, "lctrl")) then
        local dy = gui_state.input.mouse.wheel_dy
        local mx,my = gui_state.transform:unproject(gui_state.input.mouse.x, gui_state.input.mouse.y)
        ImageEditor.zoom(state, dy, mx, my)
        gui_state.input.mouse.wheel_dy = 0
    end
end

ImageEditor.draw = function(app, gui_state, state, x, y, w, h)
    -- make sure that the grid mesh is created
    if not grid_mesh then
        grid_mesh = love.graphics.newMesh(4, "fan", "stream")
    end

    local content_w, content_h
    do
        state.scrollpane_state = Scrollpane.start(gui_state, x, y, w, h, state.scrollpane_state)
        love.graphics.setColor(255, 255, 255, 255)
        love.graphics.scale(state.display.zoom, state.display.zoom)

        -- Draw background pattern
        local img_w, img_h = state.image:getDimensions()
        local backgroundquad = love.graphics.newQuad(0, 0, img_w, img_h, 2 * state.settings.grid.x,
            2 * state.settings.grid.y)
        love.graphics.draw(gui_state.style.backgroundcanvas, backgroundquad)

        love.graphics.draw(state.image)

        -- Draw the outlines of all quads
        for name, quad in pairs(state.quads) do
            show_quad(gui_state, state, quad, tostring(name))
        end

        if gui_state and gui_state.input then
            handle_input(app, gui_state, state, img_w, img_h)
        end

        -- Draw dashed lines, then clear spritebatches
        love.graphics.setColor(255, 255, 255, 255)
        love.graphics.draw(gui_state.style.dashed_line.horizontal.spritebatch)
        gui_state.style.dashed_line.horizontal.spritebatch:clear()
        love.graphics.draw(gui_state.style.dashed_line.vertical.spritebatch)
        gui_state.style.dashed_line.vertical.spritebatch:clear()

        content_w = img_w * state.display.zoom
        content_h = img_h * state.display.zoom
    end
    Scrollpane.finish(gui_state, state.scrollpane_state, content_w, content_h)
end

return ImageEditor

local current_folder = ... and (...):match '(.-%.?)[^%.]+$' or ''
local QuadExport = require(current_folder .. ".QuadExport")
local History = require(current_folder .. ".History")
local table = require(current_folder .. ".tableplus")
local libquadtastic = require(current_folder .. ".libquadtastic")
local common = require(current_folder .. ".common")
local exporters = require(current_folder .. "Exporters")
local Path = require(current_folder .. "Path")
local os = require(current_folder .. ".os")
local S = require(current_folder .. ".strings")
local Recent = require(current_folder .. "Recent")
local Grid = require(current_folder .. "Grid")
local inspect = require(current_folder .. "lib.inspect")

-- Shared library
local lfs = require("lfs")

local function add_path_to_recent_files(interface, data, filepath)
    -- Insert new file into list of recently loaded files
    -- Remove duplicates from recent files
    filepath = os.path(filepath)
    Recent.promote(data.settings.recent, filepath)
    Recent.truncate(data.settings.recent, 10)

    -- Update latest qua dir
    data.settings.latest_qua = common.split(filepath)
    interface.store_settings(data.settings)
end
local function dict_length(dict)
    local count = 0
    for _ in pairs(dict) do
        count = count + 1
    end
    return count
end

local QuadtasticLogic = {}

function QuadtasticLogic.transitions(interface)
    return {
        -- luacheck: no unused args

        quit = function(app, data)
            if not app.quadtastic.proceed_despite_unsaved_changes() then
                return
            else
                return 0
            end
        end,

        rename = function(app, data, quads)
            if not quads then quads = data.selection:get_selection() end
            if #quads == 0 then
                return
            elseif #quads > 1 then
                interface.show_dialog(S.dialogs.rename.err_only_one)
                return
            else
                local quad = quads[1]
                local current_keys = { table.find_key(data.quads, quad) }
                local old_key = table.concat(current_keys, ".")
                local new_key = old_key
                local ret
                ret, new_key = interface.query(S.dialogs.rename.name_prompt, new_key,
                    {
                        escape = S.buttons.cancel,
                        enter = S.buttons.ok
                    })

                local function replace(tab, old_keys, new_keys, element)
                    -- Make sure that the new keys form a valid path, that is, all but the
                    -- last key must be tables that are not quads
                    local current_table = tab
                    for i = 1, #new_keys do
                        if type(current_table) == "table" and libquadtastic.is_quad(current_table) then
                            local keys_so_far = table.concat(new_keys, ".", 1, i)
                            interface.show_dialog(S.dialogs.rename.err_nested_quad(keys_so_far))
                            return
                        end
                        -- This does intentionally not check the very last key, since it is
                        -- fine when that one is a quad
                        if i < #new_keys then
                            local next_key = new_keys[i]
                            -- Create a new empty table if necessary
                            if not current_table[next_key] then
                                current_table[next_key] = {}
                            end
                            current_table = current_table[next_key]
                        end
                    end

                    local do_action = function()
                        -- Remove the entry under the old key
                        table.set(data.quads, nil, unpack(old_keys))
                        -- Add the entry under the new key
                        table.set(data.quads, element, unpack(new_keys))
                    end

                    local undo_action = function()
                        -- Remove the entry under the new key
                        table.set(data.quads, nil, unpack(new_keys))
                        -- Add the entry under the old key
                        table.set(data.quads, element, unpack(old_keys))
                    end

                    data.history:add(do_action, undo_action)
                    do_action()
                    if data.turbo_workflow then app.quadtastic.turbo_workflow_on_change() end
                end

                if ret == S.buttons.ok then
                    if new_key == old_key then return end

                    local new_keys = {}
                    for k in string.gmatch(new_key, "([^.]+)") do
                        -- Convert the key to a number if possible
                        k = tonumber(k) or k
                        table.insert(new_keys, k)
                    end
                    -- Check if that key already exists
                    if table.get(data.quads, unpack(new_keys)) then
                        local action = interface.show_dialog(
                            S.dialogs.rename.err_exists(new_key),
                            { S.buttons.cancel, S.buttons.swap, S.buttons.replace })
                        if action == S.buttons.swap then
                            local old_value = table.get(data.quads, unpack(new_keys))
                            local do_action = function()
                                table.set(data.quads, old_value, unpack(current_keys))
                                table.set(data.quads, quad, unpack(new_keys))
                            end

                            local undo_action = function()
                                table.set(data.quads, old_value, unpack(new_keys))
                                table.set(data.quads, quad, unpack(current_keys))
                            end

                            data.history:add(do_action, undo_action)
                            do_action()
                            if data.turbo_workflow then
                                app.quadtastic.turbo_workflow_on_change()
                            end
                        elseif action == S.buttons.replace then
                            replace(data.quads, current_keys, new_keys, quad)
                        else -- Cancel option
                            return
                        end
                    else
                        replace(data.quads, current_keys, new_keys, quad)
                    end

                    -- Set the focus of the quad list to the renamed quad
                    interface.move_quad_into_view(data.quad_scrollpane_state, quad)
                end
            end
        end,

        rename_animation = function(app,data,state, animation_index, filter_func)
            local retry = false
            ::rename_start::
            local ret
            local new_key = state.animations[animation_index] and state.animations[animation_index].name or "New animation"
            local text = not retry and "Rename animation:" or "Name already taken\nRename animation:"
            ret, new_key = interface.query(text, new_key,
                {
                    escape = S.buttons.cancel,
                    enter = S.buttons.ok,
                }, {filter=filter_func})
            if ret == "OK" then
                for _, anim in pairs(state.animations) do
                    if anim.name == new_key and anim.index ~= animation_index then
                        retry = true
                        goto rename_start -- goto is ugly, but recalling this function instead from inside itself is weird and causes errors
                    end
                end
                if(state.animations[animation_index]) then
                    state.animations[animation_index].name = new_key
                else
                    print("Animation was with index " .. animation_index .. " not found")
                end
            end
        end,

        sort = function(app, data, quads, sort_type)
            -- local ret, new_key
            -- ret, new_key = interface.query(S.dialogs.rename.name_prompt, new_key,
            --     {
            --         escape = S.buttons.cancel,
            --         enter = S.buttons.ok
            --     })
            --Time execution
            local start_time = os.clock()
            if not quads then quads = data.selection:get_selection() end
            if #quads == 0 then return end
            -- Find the shared parent of the selected quads.
            local first_keys = { table.find_key(data.quads, quads[1]) }
            -- Remove the last element of the key list to get the shared key
            table.remove(first_keys)
            local shared_keys = first_keys
            local shared_parent = table.get(data.quads, unpack(shared_keys))
            local individual_keys = {}
            local numeric_quads = 0
            local new_group = {}
            for _, v in ipairs(quads) do
                -- This is an N^2 search and it sucks, but it probably won't matter.
                local key = table.find_key(shared_parent, v)
                if not key then
                    interface.show_dialog(S.dialogs.sort.err_not_shared_group)
                    return
                else
                    individual_keys[v] = key
                end
                if type(key) == "number" and libquadtastic.is_quad(v) then
                    numeric_quads = numeric_quads + 1
                end
            end
            if numeric_quads == 0 then
                interface.show_dialog(S.dialogs.sort.err_no_numeric_quads)
                return
            end
            for _, v in ipairs(quads) do
                if libquadtastic.is_quad(v) and type(individual_keys[v]) == "number" then
                    table.insert(new_group, v)
                end
            end
            if (sort_type == "row-major") then
                local ret
                local new_key = "15"
                ret, new_key = interface.query("Row distance threshold \n Sprites that have a Y position distance below or equal to this threshold will be considered on the same row", new_key,
                    {
                        escape = S.buttons.cancel,
                        enter = S.buttons.ok
                    }, {filter=function(c)
                        return c:match("%d")
                    end})
                if(new_key == "") then
                    new_key = "0"
                end
                if(ret == "OK") then
                    new_group = data.selection:sorted_selection_rowmajor(tonumber(new_key))
                else
                    return
                end
            else
                new_group = data.selection:sorted_selection_topleft()
            end

            local do_action = function()
                -- Remove the quads from their parent
                for _, v in ipairs(new_group) do
                    local key = individual_keys[v]
                    -- Remove the element from the shared parent
                    shared_parent[key] = nil
                end

                -- Now add the quads to the parent in order
                for _, v in ipairs(new_group) do
                    table.insert(shared_parent, v)
                end
            end
            local undo_action = function()
                for _, v in ipairs(new_group) do
                    -- Remove the quad from its shared parent, starting at the end
                    table.remove(shared_parent)
                end
                -- We cannot do this in a single pass since these actions can interfere
                for _, v in ipairs(new_group) do
                    -- Add the quads to its parent at its original position
                    local key = individual_keys[v]
                    shared_parent[key] = v
                end
            end

            data.history:add(do_action, undo_action)
            do_action()
            if data.turbo_workflow then app.quadtastic.turbo_workflow_on_change() end
            --Time execution
            local end_time = os.clock()
        end,

        remove = function(app, data, quads)
            if not quads then quads = data.selection:get_selection() end
            if #quads == 0 then
                return
            else
                local was_collapsed = {}
                local selected_elements = {}
                local keys = {}
                for _, element in ipairs(quads) do
                    if data.selection:is_selected(element) then
                        table.insert(selected_elements, element)
                    end
                    was_collapsed[element] = data.collapsed_groups[element]
                    keys[element] = { table.find_key(data.quads, element) }
                end

                local do_action = function()
                    -- Deselect those elements
                    data.selection:deselect(quads)

                    for _, element in ipairs(quads) do
                        if #keys[element] > 0 then
                            -- Remove the elements from the quad tree
                            table.set(data.quads, nil, unpack(keys[element]))
                            -- Remove the element from the list of collapsed groups. This will have
                            -- no effect if the element was a quad.
                            data.collapsed_groups[element] = nil
                        end
                    end
                end

                local undo_action = function()
                    -- Select those quads
                    data.selection:set_selection(selected_elements)

                    for _, element in ipairs(quads) do
                        if #keys[element] > 0 then
                            -- Restore the elements from the quad tree
                            table.set(data.quads, element, unpack(keys[element]))
                            -- Restore their entries from the list of collapsed groups
                            data.collapsed_groups[element] = was_collapsed[element]
                        end
                    end
                end

                data.history:add(do_action, undo_action)
                do_action()
                if data.turbo_workflow then app.quadtastic.turbo_workflow_on_change() end
            end
        end,

        create = function(app, data, new_quad)
            -- If a group is currently selected, add the new quad to that group
            -- If a quad is currently selected, add the new quad to the same
            -- group.
            local selection = data.selection:get_selection()
            local group -- the group to which the new quad will be added
            if #selection == 1 then
                local keys = { table.find_key(data.quads, selection[1]) }
                if libquadtastic.is_quad(selection[1]) then
                    -- Remove the last key so that the new quad is added to the
                    -- group that contains the currently selected quad
                    table.remove(keys)
                end
                group = table.get(data.quads, unpack(keys))
            else
                -- Just add it to the root
                group = data.quads
            end

            local do_action, undo_action
            if libquadtastic.is_quad(new_quad) then
                local new_index = #group + 1
                do_action = function()
                    group[new_index] = new_quad
                end
                undo_action = function()
                    group[new_index] = nil
                end
            else
                assert(type(new_quad) == "table")
                do_action = function()
                    for _, quad in ipairs(new_quad) do
                        table.insert(group, quad)
                    end
                end
                undo_action = function()
                    for _, quad in ipairs(new_quad) do
                        table.remove(group)
                    end
                end
            end

            data.history:add(do_action, undo_action)
            do_action()
            if data.turbo_workflow then app.quadtastic.turbo_workflow_on_change() end

            if libquadtastic.is_quad(new_quad) then
                data.selection:set_selection({ new_quad })
                interface.move_quad_into_view(data.quad_scrollpane_state, new_quad)
            else
                assert(type(new_quad) == "table")
                assert(#new_quad >= 1)
                data.selection:set_selection(new_quad)
                interface.move_quad_into_view(data.quad_scrollpane_state, new_quad[1])
            end
        end,

        --[[
                                                    _
   _ __ ___   _____   _____    __ _ _   _  __ _  __| |___
  | '_ ` _ \ / _ \ \ / / _ \  / _` | | | |/ _` |/ _` / __|
  | | | | | | (_) \ V /  __/ | (_| | |_| | (_| | (_| \__ \
  |_| |_| |_|\___/ \_/ \___|  \__, |\__,_|\__,_|\__,_|___/
                                 |_|
  ]]
        -- Moves the given quads by the given delta as far as possible.
        -- original_pos should be a table that contains the original position of each
        -- quad before the user started to move them. Each element of this table
        -- should have its x coordinate at index x and its y coordinate at index x.
        -- The nth element in original_pos should contain the coordinates of the nth
        -- quad in quads.
        -- dx, dy should be the accumulative delta by which the quads should be moved.
        -- That is, if the user moves the mouse by 4 pixels first, and then by another
        -- 8 pixels, then the delta in the second call should be 12, and not 8.
        -- All this is necessary because the movement of each quad is limited by the
        -- image's border, and therefore a quad right next to the right border cannot
        -- move as far to the right as a quad further to the left. Thus, as the user
        -- moves the quads around, we want to keep them inside the image, but we also
        -- want to preserve the relative positions of the quads. Otherwise moving all
        -- quads to the bottom right corner and them moving them in the opposite
        -- direction by the same distance would not restore the quad's original
        -- position.
        move_quads = function(app, data, quads, original_pos, dx, dy, img_w, img_h, snap_to_grid)
            if not quads then quads = data.selection:get_selection() end
            if #quads == 0 then return end
            assert(#quads == #original_pos)

            for i = 1, #quads do
                local quad = quads[i]
                local pos = original_pos[i]
                if libquadtastic.is_quad(quad) then
                    -- Offset the position by the given deltas
                    quad.x = pos.x + dx
                    quad.y = pos.y + dy

                    -- Clamp the coordinates
                    quad.x = math.max(0, math.min(img_w - quad.w, quad.x))
                    quad.y = math.max(0, math.min(img_h - quad.h, quad.y))

                    if snap_to_grid then
                        -- Snap the position of the quad to a grid point.
                        quad.x = Grid.floor(data.settings.grid.x, quad.x)
                        quad.y = Grid.floor(data.settings.grid.y, quad.y)
                    end
                end
            end
        end,

        move_origin = function(app, data, quads, original_pos, dx, dy, img_w, img_h, snap_to_grid)
            if not quads then quads = data.selection:get_selection() end
            if #quads > 1 then return end
            assert(#quads == #original_pos)
            local function clamp(x, min, max) return math.max(min, math.min(x, max)) end
            for i = 1, #quads do
                local quad = quads[i]
                local pos = original_pos[i]
                if libquadtastic.is_quad(quad) then
                    local bounds ={
                        x = quad.x,
                        y = quad.y,
                        w = quad.w,
                        h = quad.h
                    }
                    quad.ox = (pos.x + dx) / quad.w
                    quad.oy = (pos.y + dy) / quad.h

                    if snap_to_grid then
                        -- Round ox and oy to nearest 0.25
                        quad.ox = 0.25 * math.floor(quad.ox / 0.25 + 0.5)
                        quad.oy = 0.25 * math.floor(quad.oy / 0.25 + 0.5)
                    end
                end
            end
        end,

        -- Finishes moving the given quad. Without calling this function the movements
        -- that were made with move_quads are not added to the undo history.
        -- The table original_pos should follow the same format as documented in
        -- move_quads.
        commit_movement = function(app, data, quads, original_pos)
            local deltas = {} -- table containing for each quad how far it was moved
            assert(#quads == #original_pos)

            for i = 1, #quads do
                if libquadtastic.is_quad(quads[i]) then
                    deltas[i] = {
                        x = quads[i].x - original_pos[i].x,
                        y = quads[i].y - original_pos[i].y
                    }
                end
            end

            local do_action = function()
                for i = 1, #quads do
                    if libquadtastic.is_quad(quads[i]) then
                        quads[i].x = quads[i].x + deltas[i].x
                        quads[i].y = quads[i].y + deltas[i].y
                    end
                end
            end

            local undo_action = function()
                for i = 1, #quads do
                    if libquadtastic.is_quad(quads[i]) then
                        quads[i].x = quads[i].x - deltas[i].x
                        quads[i].y = quads[i].y - deltas[i].y
                    end
                end
            end

            data.history:add(do_action, undo_action)
            -- Note that we deliberately do not call the do_action here, since the quads
            -- are already at the position where the user wants them.
            if data.turbo_workflow then app.quadtastic.turbo_workflow_on_change() end
        end,

        commit_origin_movement = function(app, data, quads, original_pos)
            local deltas = {} -- table containing for each quad how far it was moved
            assert(#quads == #original_pos)

            for i = 1, #quads do
                if libquadtastic.is_quad(quads[i]) then
                    deltas[i] = {
                        x = quads[i].ox - original_pos[i].ox,
                        y = quads[i].oy - original_pos[i].oy
                    }
                end
            end

            local do_action = function()
                for i = 1, #quads do
                    if libquadtastic.is_quad(quads[i]) then
                        quads[i].ox = quads[i].ox + deltas[i].x
                        quads[i].oy = quads[i].oy + deltas[i].y
                    end
                end
            end

            local undo_action = function()
                for i = 1, #quads do
                    if libquadtastic.is_quad(quads[i]) then
                        quads[i].ox = quads[i].ox - deltas[i].x
                        quads[i].oy = quads[i].oy - deltas[i].y
                    end
                end
            end

            data.history:add(do_action, undo_action)
            -- Note that we deliberately do not call the do_action here, since the quads
            -- are already at the position where the user wants them.
            if data.turbo_workflow then app.quadtastic.turbo_workflow_on_change() end
        end,

        -- Resizes all given quads by the given amount, in the given direction.
        -- The direction should be a table containing the keys n, e, s, w when
        -- the quads are resized in the respective direction. For example, if a
        -- quad is resized at the south-east corner, then direction.s and direction.e
        -- should be set to `true`. All other keys should be `false` or `nil`.
        -- original_quad is a table that has at the nth index the original x, y, width
        -- and height at index x, y, w and h, respectively, of the nth quad in quads.
        -- The image dimensions are needed so that the position and size of the quads
        -- can be restricted.
        resize_quads = function(app, data, quads, original_quad, direction, dx, dy, img_w, img_h, snap_to_grid)
            dx, dy = dx or 0, dy or 0
            -- All quads have their position in the upper left corner, and their
            -- size extends to the lower right corner.

            -- The change in position to be applied to all quads
            local dpx, dpy = 0, 0

            -- The change in size to be applied to all quads
            local dw, dh = 0, 0

            if direction.n and dy ~= 0 then
                dpy = dy -- move the quad by the given amount
                dh = -dy -- but reduce the height accordingly
            elseif direction.s and dy ~= 0 then
                dh = dy
            end

            if direction.w and dx ~= 0 then
                dpx = dx -- move the quad by the given amount
                dw = -dx -- but reduce the height accordingly
            elseif direction.e and dx ~= 0 then
                dw = dx
            end

            -- Now apply all changes
            for i, quad in pairs(quads) do
                local ox, oy = original_quad[i].x, original_quad[i].y
                local ow, oh = original_quad[i].w, original_quad[i].h

                -- Calculate deltas specific to this quad in case we need to snap the
                -- quad size to the grid
                local idpx, idpy, idw, idh = dpx, dpy, dw, dh
                if snap_to_grid then
                    local gx, gy = data.settings.grid.x, data.settings.grid.y
                    local grid_w, grid_h = Grid.mult(gx, ow + dx), Grid.mult(gy, oh + dy)
                    -- deltas after grid snapping
                    local gdx, gdy = grid_w - ow - dx, grid_h - oh - dy

                    -- Adjust position and size deltas
                    if direction.n then
                        idpy = idpy + gdy
                        idh = idh - gdy
                    elseif direction.s then
                        idh = idh + gdy
                    end

                    if direction.w then
                        idpx = idpx + gdx
                        idw = idw - gdx
                    elseif direction.e then
                        idw = idw + gdx
                    end
                end

                -- Resize the quads, but restrict their dimensions and position
                quad.x = math.max(0, math.min(img_w, ox + math.min(ow - 1, idpx)))
                quad.y = math.max(0, math.min(img_h, oy + math.min(oh - 1, idpy)))
                quad.w = math.max(1, math.min(img_w - quad.x,
                    ow + (direction.w and math.min(ox, idw) or idw)))
                quad.h = math.max(1, math.min(img_h - quad.y,
                    oh + (direction.n and math.min(oy, idh) or idh)))
            end
        end,

        commit_resizing = function(app, data, quads, original_quad)
            local deltas = {}
            assert(#quads == #original_quad)
            for i = 1, #quads do
                if libquadtastic.is_quad(quads[i]) then
                    deltas[i] = {
                        x = quads[i].x - original_quad[i].x,
                        y = quads[i].y - original_quad[i].y,
                        w = quads[i].w - original_quad[i].w,
                        h = quads[i].h - original_quad[i].h,
                    }
                end
            end

            local do_action = function()
                for i = 1, #quads do
                    if libquadtastic.is_quad(quads[i]) then
                        quads[i].x = quads[i].x + deltas[i].x
                        quads[i].y = quads[i].y + deltas[i].y
                        quads[i].w = quads[i].w + deltas[i].w
                        quads[i].h = quads[i].h + deltas[i].h
                    end
                end
            end

            local undo_action = function()
                for i = 1, #quads do
                    if libquadtastic.is_quad(quads[i]) then
                        quads[i].x = quads[i].x - deltas[i].x
                        quads[i].y = quads[i].y - deltas[i].y
                        quads[i].w = quads[i].w - deltas[i].w
                        quads[i].h = quads[i].h - deltas[i].h
                    end
                end
            end

            data.history:add(do_action, undo_action)
            -- Note that we deliberately do not call the do_action here, since the quads
            -- are already resized to the size that the user wants.
            if data.turbo_workflow then app.quadtastic.turbo_workflow_on_change() end
        end,

        group = function(app, data, quads)
            if not quads then quads = data.selection:get_selection() end
            if #quads == 0 then return end
            -- Find the shared parent of the selected quads.
            local first_keys = { table.find_key(data.quads, quads[1]) }
            -- Remove the last element of the key list to get the shared key
            table.remove(first_keys)
            local shared_keys = first_keys
            local shared_parent = table.get(data.quads, unpack(shared_keys))
            local individual_keys = {}
            for _, v in ipairs(quads) do
                -- This is an N^2 search and it sucks, but it probably won't matter.
                local key = table.find_key(shared_parent, v)
                if not key then
                    interface.show_dialog(S.dialogs.group.err_not_shared_group)
                    return
                else
                    individual_keys[v] = key
                end
            end

            -- Do the second pass, this time with destructive actions
            local new_group = {}
            local numeric_indices = {}
            for _, v in ipairs(quads) do
                local key = individual_keys[v]
                -- We don't necessarily want to preserve the numeric index, but we do
                -- want to preserve the order of those quads with numeric indices
                if type(key) == "number" then
                    table.insert(numeric_indices, key)
                else
                    new_group[key] = v
                end
            end

            table.sort(numeric_indices)
            for i, old_key in ipairs(numeric_indices) do
                new_group[i] = shared_parent[old_key]
            end

            local do_action = function()
                for _, v in ipairs(quads) do
                    -- Remove the element from the shared parent
                    local key = individual_keys[v]
                    shared_parent[key] = nil
                end
                table.insert(shared_parent, new_group)

                -- Focus quad list on new group
                interface.move_quad_into_view(data.quad_scrollpane_state, new_group)
                -- Select the newly created group
                data.selection:set_selection({ new_group })
            end

            local undo_action = function()
                for _, v in ipairs(quads) do
                    -- Restore the element in its original position in shared parent
                    local key = individual_keys[v]
                    shared_parent[key] = v
                end
                -- We used a simple insert to add the new group to the parent.
                -- Therefore the group was inserted at the very end of the parent, and
                -- can be removed with table.remove
                table.remove(shared_parent)
            end

            data.history:add(do_action, undo_action)
            do_action()
            if data.turbo_workflow then app.quadtastic.turbo_workflow_on_change() end
        end,

        ungroup = function(app, data, quads)
            if not quads then quads = data.selection:get_selection() end
            if #quads == 0 then return end
            if #quads > 1 then
                interface.show_dialog(S.dialogs.ungroup.err_only_one)
                return
            end
            if libquadtastic.is_quad(quads[1]) then
                return
            end

            local group = quads[1]
            local keys = { table.find_key(data.quads, group) }
            -- Remove the last element of the key list to get the parent's keys
            local group_key = table.remove(keys)
            local parent_keys = keys
            local parent = table.get(data.quads, unpack(parent_keys))

            -- Check that we can break up this group by making sure that the parent
            -- element and the group don't have any conflicting keys
            local ignore_numeric_clash = false
            for k, _ in pairs(group) do
                if parent[k] and k ~= group_key then
                    local parent_name
                    for _, v in ipairs(parent_keys) do
                        parent_name = (parent_name and (parent_name .. ".") or "") .. tostring(v)
                    end
                    if type(k) == "number" then
                        if not ignore_numeric_clash then
                            local ret = interface.show_dialog(S.dialogs.ungroup.warn_numeric_clash(k),
                                { S.buttons.yes, S.buttons.no })
                            if ret == S.buttons.yes then
                                ignore_numeric_clash = true
                            else
                                return
                            end
                        end
                    else
                        interface.show_dialog(S.dialogs.ungroup.err_name_conflict(k))
                        return
                    end
                end
            end

            local do_action = function()
                -- Remove group from parent
                parent[group_key] = nil

                data.collapsed_groups[group_key] = nil
                for k, v in pairs(group) do
                    if type(k) == "number" then
                        table.insert(parent, v)
                    else
                        parent[k] = v
                    end
                end
            end

            local undo_action = function()
                -- Remove the group's elements from the parent
                for k, v in pairs(group) do
                    if type(k) == "number" then
                        table.remove(parent)
                    else
                        parent[k] = nil
                    end
                end

                -- Add the group to the parent
                parent[group_key] = group
            end
            data.history:add(do_action, undo_action)
            do_action()
            if data.turbo_workflow then app.quadtastic.turbo_workflow_on_change() end
        end,

        offer_reload = function(app, data, callback)
            local image_path = data.quads._META.image_path
            local ret = interface.show_dialog(
                S.dialogs.offer_reload(image_path),
                { enter = S.buttons.yes, escape = S.buttons.no })
            if ret == S.buttons.yes then
                app.quadtastic.load_image(image_path, callback)
            end
        end,

        undo = function(app, data)
            if not data.history:can_undo() then return end
            local undo_action = data.history:undo()
            undo_action()
            if data.turbo_workflow then app.quadtastic.turbo_workflow_on_change() end
        end,

        redo = function(app, data)
            if not data.history:can_redo() then return end
            local redo_action = data.history:redo()
            redo_action()
            if data.turbo_workflow then app.quadtastic.turbo_workflow_on_change() end
        end,

        new = function(app, data)
            local proceed = app.quadtastic.proceed_despite_unsaved_changes()
            if not proceed then return end

            data.quads = {
                _META = {}
            }
            data.quadpath = nil -- path to the file containing the quad definitions
            -- The name of the last used exporter
            data.prev_exporter = nil
            -- A mapping from exporter name to last used path. This is convenient
            -- in case specific export targets are always saved in the same location.
            -- These are populated from the loaded application settings.
            data.exportpath = {}
            data.image = nil -- the loaded image
            interface.reset_view(data)
            -- Reset list of collapsed groups
            data.collapsed_groups = {}

            data.file_timestamps = {}
            data.history = History()
            data.history:mark() -- A new file doesn't have any changes worth saving
            -- until the user actually does something

            app.quadtastic.switch_tool("create")
        end,

        -- The steps that need to be taken when turbo workflow is enabled and
        -- some quads changed.
        turbo_workflow_on_change = function(app, data)
            app.quadtastic.save()
            if data.prev_exporter then
                app.quadtastic.repeat_export()
            end
        end,

        switch_tool = function(app, data, tool)
            data.tool = tool
            data.toolstate = {}
        end,

        save = function(app, data, callback)
            if not data.quadpath or data.quadpath == "" then
                app.quadtastic.save_as(callback)
            else
                print(inspect(common.exporter_table))
                local success, err = pcall(app.quadtastic.export_with, data.quadpath, common.exporter_table)
                if success then
                    data.history:mark()
                    if callback then callback(data.quadpath) end
                else
                    interface.show_dialog(S.dialogs.err_save_quads(err))
                end
            end
        end,

        -- Have user pick a path where to save the quad file.
        -- This is separate from export_as so that data.quadpath and data.exportpath
        -- don't get mixed up.
        save_as = function(app, data, callback)
            local basepath

            if data.quadpath then
                basepath = data.quadpath
            elseif data.quads and data.quads._META and data.quads._META.image_path then
                basepath = common.split(data.quads._META.image_path)
            elseif data.settings.latest_qua then
                basepath = data.settings.latest_qua
            else
                basepath = love.filesystem.getUserDirectory()
            end

            local ret, filepath = interface.save_file(basepath, "lua")
            if ret == S.buttons.save then
                data.quadpath = filepath
                -- pass a callback to the save function that stores the used path in the
                -- list of recently opened files if saving succeeded.
                local function save_as_callback(quadpath)
                    add_path_to_recent_files(interface, data, quadpath)
                    if callback then callback(quadpath) end
                end
                app.quadtastic.save(save_as_callback)
            end
        end,

        -- Exports the current quads to the previously used file, using the previously
        -- used exporter.
        repeat_export = function(app, data, callback)
            if not data.prev_exporter then return end

            local exporter = data.prev_exporter
            if not data.exportpath[exporter.name] then
                -- Have user pick an export file
                app.quadtastic.export_as(exporter, callback)
            else
                local path = data.exportpath[exporter.name]

                -- Check that the exporter can indeed export the quad definitions.
                -- If the exporter does not define this function, we assume that it can
                -- export everything.
                if exporter.can_export then
                    local success, can_export, msg = pcall(exporter.can_export, data.quads)
                    if success then
                        if not can_export then
                            interface.show_dialog(S.dialogs.err_cannot_export(msg))
                            return
                        end
                    else
                        local err = can_export -- the second returned value contains the error
                        interface.show_dialog(S.dialogs.err_exporting(err))
                        return
                    end
                end
                
                local success, err = pcall(app.quadtastic.export_with, path, exporter)
                if success then
                    if callback then callback(path) end
                else
                    interface.show_dialog(S.dialogs.err_exporting(err))
                end
            end
        end,

        -- Exports the current quads using the given exporter. The user will be asked
        -- to pick a file.
        export_as = function(app, data, exporter, callback)
            local basepath

            if data.exportpath[exporter.name] then
                basepath = data.exportpath[exporter.name]
            elseif data.quadpath then
                local path, filename = common.split(data.quadpath)
                local export_filename = string.format("%s.%s",
                    Path.split_extension(filename),
                    exporter.ext)
                basepath = path .. export_filename
            elseif data.quads and data.quads._META and data.quads._META.image_path then
                basepath = common.split(data.quads._META.image_path)
            elseif data.settings.latest_qua then
                basepath = data.settings.latest_qua
            else
                basepath = love.filesystem.getUserDirectory()
            end

            local save_button_label = S.buttons.export_as(exporter.name)
            local ret, filepath = interface.save_file(basepath, exporter.ext,
                save_button_label)
            if ret == save_button_label then
                -- Store that path, so that the file browser starts off at that path in
                -- the future for this exporter.
                data.exportpath[exporter.name] = filepath
                data.prev_exporter = exporter
                app.quadtastic.repeat_export(callback)
            end
        end,
        -- expect this function to fail! Wrap it in a pcall!
        export_with = function(app, data, path, exporter)
            QuadExport.export({quads=data.quads,animations=data.animations}, exporter, path)
        end,

        choose_quad = function(app, data, basepath)
            if not basepath and data.settings.latest_qua then
                basepath = data.settings.latest_qua
            else
                basepath = love.filesystem.getUserDirectory()
            end
            local ret, filepath = interface.open_file(basepath)
            if ret == S.buttons.open then
                app.quadtastic.load_quad(filepath)
            end
        end,

        -- Checks with the user how they want to handle unsaved changes before an
        -- action is executed that would override those changes.
        -- The user can save or discard the changes, or cancel the action.
        -- This function returns whether the user chose an action that indicates that
        -- they want to go ahead with the action (i.e. the function returns true if
        -- the user pressed save or discard, false otherwise).
        -- This function will also return true if there are no unsaved changes.
        proceed_despite_unsaved_changes = function(app, data)
            -- Return true if there are no unsaved changes
            if not data.history or data.history:is_marked() then return true end

            -- Otherwise check with the user
            local ret = interface.show_dialog(S.dialogs.save_changes,
                { S.buttons.cancel, S.buttons.discard, S.buttons.save })
            if ret == S.buttons.save then
                app.quadtastic.save()
            end
            return ret == S.buttons.save or ret == S.buttons.discard
        end,

        load_quad = function(app, data, filepath)
            if not app.quadtastic.proceed_despite_unsaved_changes() then return end
            local success, more = pcall(function()
                local filehandle, err = io.open(filepath, "r")
                if err then
                    error(err, 0)
                end

                if filehandle then
                    filehandle:close()
                    local filecontent, load_err = loadfile(filepath)
                    if not filecontent then
                        error(load_err, 0)
                    end
                    local quads = filecontent()
                    local quadpath = filepath
                    return { quads, quadpath }
                end
            end)
            if success then
                local save_data, path = unpack(more)
                local new_saveformat = save_data["quads"]~=nil and save_data["animations"]~=nil
                print(new_saveformat)
                if(new_saveformat) then
                    data.quads, data.quadpath = save_data.quads, path
                    data.animations = save_data.animations or {}
                else
                    --[[
                        Old save format before animations were introduced.
                    ]]
                    data.quads,data.quadpath = save_data, path
                    data.animations = {}
                end
                -- Reset list of collapsed groups
                data.collapsed_groups = {}
                data.history = History()
                -- A newly loaded project has no unsaved changes
                data.history:mark()
                if not data.quads._META then data.quads._META = {} end
                local metainfo = libquadtastic.get_metainfo(data.quads)

                -- Remove the current image from the application state
                data.image = nil

                if metainfo.image_path then
                    local abs_path
                    if Path.is_absolute_path(metainfo.image_path) then
                        abs_path = metainfo.image_path
                    elseif Path.is_relative_path(metainfo.image_path) then
                        -- Create an absolute path to the image file by concatenating the
                        -- absolute path to the directory containing the quadfile and the
                        -- relative image path
                        abs_path = tostring(Path(filepath):parent() .. metainfo.image_path)
                    else
                        error("Path to image is neither absolute nor relative.")
                    end
                    -- Store the image path as an absolute path. It will be converted back
                    -- to a relative path when the quads are saved or exported.
                    metainfo.image_path = abs_path
                    app.quadtastic.load_image(metainfo.image_path)
                end

                add_path_to_recent_files(interface, data, filepath)
            else
                interface.show_dialog(S.dialogs.err_load_quads(more))
            end
        end,

        choose_image = function(app, data, basepath)
            if not basepath then
                if data.quads and data.quads._META and data.quads._META.image_path then
                    basepath = data.quads._META.image_path
                elseif data.settings.latest_img then
                    basepath = data.settings.latest_img
                else
                    basepath = love.filesystem.getUserDirectory()
                end
            end
            local ret, filepath = interface.open_file(basepath)
            if ret == S.buttons.open then
                app.quadtastic.load_image(filepath)
            end
        end,

        load_image = function(app, data, filepath, callback)
            filepath = os.path(filepath)
            local success, more = pcall(common.load_image, filepath)

            -- success, more = pcall(love.graphics.newImage, data)
            if success then
                data.image = more
                data.quads._META.image_path = filepath

                -- Update latest image dir
                data.settings.latest_img = common.split(filepath)
                interface.store_settings(data.settings)

                data.file_timestamps.image_loaded = lfs.attributes(filepath, "modification")
                data.file_timestamps.image_latest = data.file_timestamps.image_loaded
                interface.reset_view(data)
                if callback then callback(filepath) end
            else
                interface.show_dialog(S.dialogs.err_load_image(more))
            end
        end,

        load_dropped_file = function(app, data, filepath)
            -- Determine how to treat this file depending on its extensions
            local _, extension = Path.split_extension(filepath)
            if extension == "lua" or extension == "qua" then
                app.quadtastic.load_quad(filepath)
            else
                -- Try to load this as an image
                app.quadtastic.load_image(filepath)
            end
        end,

        -- Change the current grid configuration to the given grid configuration,
        -- update the list of recent grid configurations and save the changed settings
        change_grid_config = function(app, state, grid_x, grid_y)
            -- Promote current config to the most recently used config
            local comparator = function(conf_a, conf_b)
                return conf_a.x == conf_b.x and conf_a.y == conf_b.y
            end
            local current_config = {
                x = state.settings.grid.x,
                y = state.settings.grid.y
            }
            Recent.promote(state.settings.grid.recent, current_config,
                comparator)

            -- Remove the new entry from the list of recent entries.
            -- Otherwise it is shown as the current configs, but might show
            -- up in the list of recent configs, too.
            Recent.remove(state.settings.grid.recent, { x = grid_x, y = grid_y },
                comparator)
            Recent.truncate(state.settings.grid.recent, 10)

            -- Update current config
            state.settings.grid.x = grid_x
            state.settings.grid.y = grid_y

            -- Save settings
            interface.store_settings(state.settings)
        end,

        -- Open a dialog that lets the user pick custom grid configuration.
        -- When the user confirms the dialog, change the grid config to the chosen
        -- grid config.
        choose_custom_grid_config = function(app, state)
            local ret, new_grid = interface.choose_grid_config(state.settings.grid.x,
                state.settings.grid.y)
            if ret == S.buttons.ok then
                app.quadtastic.change_grid_config(new_grid.x, new_grid.y)
            end
        end,

        reload_exporters = function(app, data, callback)
            local success, more, count = pcall(exporters.list, { S.exporters_dirname,
                S.custom_exporters_dirname })
            if success then
                data.exporters = more
                -- Update previous exporter
                if data.prev_exporter then
                    -- This will clear the previous exporter if there is none with that
                    -- name in the new set of exporters, or update the previous exporter.
                    data.prev_exporter = data.exporters[data.prev_exporter.name]
                end
                if callback then callback(count) end
            else
                interface.show_dialog(S.dialogs.err_reload_exporters(more))
            end
        end,

        show_about_dialog = function(app, data)
            interface.show_about_dialog()
        end,

        show_ack_dialog = function(app, data)
            interface.show_ack_dialog()
        end,

        check_updates = function(app, data)
            interface.check_updates()
        end,

        offer_update = function(app, data, current_version, latest_version)
            local ret = interface.show_dialog(S.dialogs.offer_update(latest_version,
                    current_version),
                { enter = S.buttons.yes, escape = S.buttons.no })
            if ret == S.buttons.yes then
                love.system.openURL(S.itchio_url)
            end
        end,

    }
end

return QuadtasticLogic

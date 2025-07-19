local current_folder = ... and (...):match '(.-%.?)[^%.]+$' or ''
local table = require(current_folder .. ".tableplus")
local Selection = {}

Selection.is_selected = function(self, v) return self.selection[v] end

-- Clear the current selection
Selection.clear_selection = function(self) self.selection = {} end

-- Repace the current selection by the given selection
Selection.set_selection = function(self, quads)
    Selection.clear_selection(self)
    Selection.select(self, quads)
end

-- Add the given quads or table of quads to the selection
Selection.select = function(self, quads)
    for _, v in ipairs(quads) do self.selection[v] = true end
end

-- Remove the given quads from the selection.
-- If a table of quads is passed, the table and all contained quads will be
-- removed from the selection.
Selection.deselect = function(self, quads)
    for _, v in ipairs(quads) do self.selection[v] = nil end
end

Selection.get_selection = function(self)
    return table.keys(self.selection)
end


--[[
  Unused, was created for testing my theory of if creating a bounding box
  around the selection and then sorting the quads by the distance from
  their top left corner to the top left corner of the bounding box would
  work better than the now old method of sorting by y position and then x
  position.

  Keeping it here incase it has other uses that appear in the future.
]]
Selection.get_selection_bounds = function(self)
    local min_x, min_y, max_x, max_y = math.huge, math.huge, -math.huge,
        -math.huge
    for _, v in ipairs(self:get_selection()) do
        local x = v.x
        local y = v.y
        local w = v.w
        local h = v.h
        local ox = v.ox
        local oy = v.oy
        -- Create minimum bounding box around all selected quads
        min_x = math.min(min_x, x)
        min_y = math.min(min_y, y)
        max_x = math.max(max_x, x + w)
        max_y = math.max(max_y, y + h)
    end
    return min_x, min_y, max_x, max_y
end

-- Returns a table of quads sorted using the row major order method
Selection.sorted_selection_topleft = function(self)
    local function sort(quad_a, quad_b)
        return quad_a.y < quad_b.y or quad_a.y == quad_b.y and quad_a.x < quad_b.x
    end
    local sorted_quads = self:get_selection()
    table.sort(sorted_quads, sort)
    return sorted_quads
end

Selection.sorted_selection_rowmajor = function(self)
    local rows = {}
    local row_threshold = 15
    -- Loop through selection and get rows by finding quads with the same y value or within a certain threshold
    for _, v in ipairs(self:get_selection()) do
        local row = {}
        for _, v2 in ipairs(self:get_selection()) do
            if math.abs(v.y - v2.y) < row_threshold then
                table.insert(row, v2)
            end
        end
        -- Make sure we don't add the same row twice
        if (table.contains(rows, row) == false) then
            table.insert(rows, row)
        end
    end
    -- Sort rows by y value
    table.sort(rows, function(a, b) return a[1].y < b[1].y end)
    -- Sort each row by x value
    for _, v in ipairs(rows) do
        table.sort(v, function(a, b) return a.x < b.x end)
    end
    -- Put all quads in a single table
    local sorted_quads = {}
    for _, v in ipairs(rows) do
        for _, v2 in ipairs(v) do table.insert(sorted_quads, v2) end
    end
    return sorted_quads
end



Selection.new = function(_)
    local selection = {
        selection = {} -- the actual table that contains selected elements
    }

    setmetatable(selection, { __index = Selection })

    return selection
end

setmetatable(Selection, { __call = Selection.new })

return Selection

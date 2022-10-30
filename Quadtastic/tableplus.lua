local tableplus = {}

setmetatable(tableplus, {
  __index = function(_, key)
    return rawget(tableplus, key) or table[key]
  end
})

-- Returns table[key][...]
-- That is, get(t, k1, k2, k3) is another way to write t[k1][k2][k3]
-- but there is no built-in way in Lua to do this in an automated way
function tableplus.get(tab, key, ...)
  if tab == nil then return nil
  elseif not key then
    -- this covers the case table.get(tab)
    return tab
  elseif select("#", ...) == 0 then
    return tab[key]
  else
    -- apply recursively
    return tableplus.get(tab[key], ...)
  end
end

-- Sets table[key][...] to value
-- That is, _set(t, v, k1, k2, k3) is another way to write t[k1][k2][k3] = v
-- but there is no built-in way in Lua to do this in an automated way
function tableplus.set(tab, value, key, ...)
  if select("#", ...) == 0 then
    tab[key] = value
  else
    -- apply recursively
    tableplus.set(tab[key], value, ...)
  end
end

-- Tries to find the list of keys that point to a specific value.
-- Performs a depth-first-search through the given table.
-- Therefore matching items that are nested deeper in the table might be
-- returned even though matching items on higher levels exist.
function tableplus.find_key(tab, value)
  for k,v in pairs(tab) do
    if v == value then return k
    elseif type(v) == "table" then -- search recursively
      -- Return a list of keys
      local result = {tableplus.find_key(v, value)}
      if #result > 0 then return k, unpack(result) end
    end
  end
  return nil
end

function tableplus.keys(tab)
  local keys = {}
  for k, _ in pairs(tab) do
    tableplus.insert(keys, k)
  end
  return keys
end

function tableplus.values(tab)
  local values = {}
  for _, v in pairs(tab) do
    tableplus.insert(values, v)
  end
  return values
end

-- Returns a new table that contains the values of a and b without duplicates
function tableplus.union(a, b)
  local union = {}
  local seen = {}
  for _, v in pairs(a) do
    table.insert(union, v)
    seen[v] = true
  end
  for _, v in pairs(b) do
    if not seen[v] then table.insert(union, v) end
  end
  return union
end

-- Compares the contents of the two tables in a shallow manner. That is, it will
-- make sure that the two tables have the same number of arguments, the same
-- numeric values, and that the keys and values of both tables are equal.
function tableplus.shallow_equals(a, b)
  if not type(a) == "table" then error("The first parameter is not a table") end
  if not type(b) == "table" then error("The second parameter is not a table") end
  for k,v in pairs(a) do
    if not b[k] == v then return false end
  end
  for k,v in pairs(b) do
    if not a[k] == v then return false end
  end
  return true
end

function table.equals(o1, o2, ignore_mt)
  if o1 == o2 then return true end
  local o1Type = type(o1)
  local o2Type = type(o2)
  if o1Type ~= o2Type then return false end
  if o1Type ~= 'table' then return false end

  if not ignore_mt then
      local mt1 = getmetatable(o1)
      if mt1 and mt1.__eq then
          --compare using built in method
          return o1 == o2
      end
  end

  local keySet = {}

  for key1, value1 in pairs(o1) do
      local value2 = o2[key1]
      if value2 == nil or tableplus.equals(value1, value2, ignore_mt) == false then
          return false
      end
      keySet[key1] = true
  end

  for key2, _ in pairs(o2) do
      if not keySet[key2] then return false end
  end
  return true
end

function tableplus.contains(t, what)
  --Check if t contains what assuming what is a table
  for _, v in pairs(t) do
    print(v,what)
    if table.equals(v, what,true) then return true end
  end
  return false
end


return tableplus
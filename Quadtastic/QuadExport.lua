local current_folder = ... and (...):match '(.-%.?)[^%.]+$' or ''
local common = require(current_folder .. ".common")
local Path = require(current_folder .. ".Path")
local inspect = require(current_folder.."lib.inspect")

local QuadExport = {}

QuadExport.export = function(exporting, exporter, filepath)
  --Save the filepath to the love2D save directory
  print(filepath)
  local success, message = love.filesystem.write("filepath.txt", filepath)
  print(inspect(exporting))
  assert(exporting.quads and type(exporting.quads) == "table")
  assert(exporter and type(exporter) == "table", tostring(type(exporter)))
  assert(exporter.export and type(exporter.export) == "function")
  assert(exporter.ext and type(exporter.ext) == "string")
  assert(exporter.name and type(exporter.name) == "string")


  -- Use clone of quads table instead of the original one
  local save_data_clone = common.clone({quads = exporting.quads, animations = exporting.animations})

  local filehandle, open_err = io.open(filepath, "w")
  if not filehandle then error(open_err) end

  if not save_data_clone.quads._META then save_data_clone.quads._META = {} end

  -- Insert version info into quads
  save_data_clone.quads._META.version = common.get_version()

  -- Replace the path to the image by a path name relative to the parent dir of
  -- `filepath`. We use the parent dir since filepath points to the file that
  -- the quads will be exported to.
  if save_data_clone.quads._META.image_path then
    assert(Path.is_absolute_path(filepath))
    local basepath = Path(filepath):parent()
    assert(Path.is_absolute_path(save_data_clone.quads._META.image_path))
    local rel_path = Path(save_data_clone.quads._META.image_path):get_relative_to(basepath)
    save_data_clone.quads._META.image_path = rel_path
  end

  local writer = common.get_writer(filehandle)
  local info = {
    filepath = filepath,
  }
  local success, export_err = pcall(exporter.export, writer, save_data_clone, info)
  filehandle:close()

  if not success then error(export_err, 0) end
end

return QuadExport

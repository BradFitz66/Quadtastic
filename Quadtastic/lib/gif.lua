local gifwriter = {}
gifwriter.__index = gifwriter

local function num2str(value)
	return string.char(value % 256, math.floor(value / 256))
end

local function encode(indices)
	local output = {}
	local packed, bits = 0, 0
	local dictionary, next_code, code_size = {}, 258, 9
	local function emit(code)
		packed = packed + code * 2 ^ bits
		bits = bits + code_size
		while bits >= 8 do
			output[#output + 1] = string.char(packed % 256)
			packed = math.floor(packed / 256)
			bits = bits - 8
		end
	end
	emit(256)
	local prefix = indices[1]
	for position = 2, #indices do
		local index = indices[position]
		local key = prefix * 256 + index
		if dictionary[key] then
			prefix = dictionary[key]
		else
			emit(prefix)
			if next_code < 4096 then
				dictionary[key] = next_code
				next_code = next_code + 1
				if next_code > 2 ^ code_size then
					code_size = code_size + 1
				end
			else
				emit(256)
				dictionary, next_code, code_size = {}, 258, 9
			end
			prefix = index
		end
	end
	emit(prefix)
	if next_code == 2 ^ code_size and code_size < 12 then
		code_size = code_size + 1
	end
	emit(257)
	if bits > 0 then
		output[#output + 1] = string.char(packed % 256)
	end
	local data = table.concat(output)
	local blocks = {"\8"}
	for position = 1, #data, 255 do
		local block = data:sub(position, position + 254)
		blocks[#blocks + 1] = string.char(#block) .. block
	end
	blocks[#blocks + 1] = "\0"
	return table.concat(blocks)
end

function gifwriter.new(filename, width, height, palette)
	assert(width > 0 and width <= 65535 and width % 1 == 0, "Invalid GIF width")
	assert(height > 0 and height <= 65535 and height % 1 == 0, "Invalid GIF height")
	assert(not palette or (#palette > 0 and #palette <= 255), "GIF supports up to 255 opaque colors")
	return setmetatable({filename = filename, width = width, height = height,
						 palette = palette, data = {}}, gifwriter)
end

function gifwriter:begin(write, loop)
	self.write = write or function(data) self.data[#self.data + 1] = data end
	self.write("GIF89a" .. num2str(self.width) .. num2str(self.height) .. "\240\0\0"
			   .. string.rep("\0", 6))
	if loop then
		self.write("\33\255\11NETSCAPE2.0\3\1\0\0\0")
	end
end

function gifwriter:write_frame(data, delay)
	assert(self.write, "Call begin before writing GIF frames")
	local major = love and love.getVersion and love.getVersion() or 11
	local scale = major >= 11 and 255 or 1
	local pixels, palette, lookup = {}, {}, {}
	local overflow = false
	if self.palette then
		for index, color in ipairs(self.palette) do
			palette[index] = color
		end
	end
	for row = 0, self.height - 1 do
		for column = 0, self.width - 1 do
			local red, green, blue, alpha = data:getPixel(column, row)
			red = math.floor(red * scale + 0.5)
			green = math.floor(green * scale + 0.5)
			blue = math.floor(blue * scale + 0.5)
			if (alpha or 255 / scale) * scale < 128 then
				pixels[#pixels + 1] = false
			else
				local key = red * 65536 + green * 256 + blue
				pixels[#pixels + 1] = {red, green, blue}
				if not self.palette and not lookup[key] then
					if #palette < 255 then
						palette[#palette + 1] = {red, green, blue}
						lookup[key] = #palette
					else
						overflow = true
					end
				end
			end
		end
	end
	if overflow then
		palette = {}
		for red = 0, 5 do
			for green = 0, 5 do
				for blue = 0, 5 do
					palette[#palette + 1] = {red * 51, green * 51, blue * 51}
				end
			end
		end
	end
	local indices = {}
	for position, color in ipairs(pixels) do
		local index = 0
		if color then
			if overflow then
				index = math.floor(color[1] / 51 + 0.5) * 36
					  + math.floor(color[2] / 51 + 0.5) * 6
					  + math.floor(color[3] / 51 + 0.5) + 1
			elseif self.palette then
				local distance = math.huge
				for candidate, entry in ipairs(palette) do
					local delta = (color[1] - entry[1]) ^ 2 + (color[2] - entry[2]) ^ 2
								+ (color[3] - entry[3]) ^ 2
					if delta < distance then
						index, distance = candidate, delta
					end
				end
			else
				index = lookup[color[1] * 65536 + color[2] * 256 + color[3]]
			end
		end
		indices[position] = index
	end
	local colors = {"\0\0\0"}
	for _, color in ipairs(palette) do
		colors[#colors + 1] = string.char(unpack(color))
	end
	colors[#colors + 1] = string.rep("\0\0\0", 255 - #palette)
	delay = math.max(1, math.min(65535, math.floor((delay or 100) / 10 + 0.5)))
	self.write("\33\249\4\9" .. num2str(delay) .. "\0\0")
	self.write("\44\0\0\0\0" .. num2str(self.width) .. num2str(self.height) .. "\135")
	self.write(table.concat(colors))
	self.write(encode(indices))
end

function gifwriter:finish()
	assert(self.write, "Call begin before finishing a GIF")
	self.write("\59")
	self.write = nil
	return table.concat(self.data)
end

return gifwriter
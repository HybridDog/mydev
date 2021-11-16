
-- Not helpful because a click on an image doesn't get passed to the scrollbars
-- A background works but is behind the semi-transparent bars
local function make_barfield(x, y, w, h, num_bars, identifier, spec)
	local bar_height = h / num_bars
	-- The thumb size is usually equal to the bar height
	spec[#spec+1] = "scrollbaroptions[arrows=hide]"
	for k = 0, num_bars-1 do
		-- Extend the width and positioning so that clicking on outer positions
		-- is possible
		local bar_x = x - 0.5 * bar_height
		local bar_y = y + k * bar_height
		local bar_w = w + bar_height
		spec[#spec+1] = ("scrollbar[%g,%g;%g,%g;;_%s%d;]"):format(
			bar_x, bar_y, bar_w, bar_height, identifier, k)
	end
end

local function table_colourfield(x, y, w, h, colours, spec)
	-- Unimplemented / unfinished
	--~ local num_colours = #colours
	spec[#spec+1] = "style_type[table;font=mono]"
	spec[#spec+1] = "tableoptions[background=#00008080]"
	--~ spec[#spec+1] = "tablecolumns[color,padding=0;text,padding=0;color,padding=0;text,padding=0]"
	--~ spec[#spec+1] = ("table[%g,%g;%g,%g;mytable;%s,██,%s,██]"):format(
		--~ x, y, w, h, colours[1], colours[2])
	spec[#spec+1] = "tablecolumns[text,padding=0;text,padding=0]"
	spec[#spec+1] = ("table[%g,%g;%g,%g;mytable;██,██,██]"):format(
		x, y, w, h)
end

local function vertical_gradient(x, y, w, h, colours, spec)
	local eh = h / (#colours - 1)
	local bg_cols = {{y, eh, 1}}
	spec[#spec+1] = ("box[%g,%g;%g,%g;%s]"):format(x, y, w, eh, colours[1])
	for k = 3, #colours-1, 2 do
		bg_cols[#bg_cols+1] = {y + (k - 2) * eh, 2.0 * eh, k}
	end
	if #colours % 2 == 1 then
		bg_cols[#bg_cols+1] = {y + (#colours - 2) * eh, eh, #colours}
	end
	local fg_cols = {{y, 2}}
	for k = 4, #colours, 2 do
		fg_cols[#fg_cols+1] = {y + (k - 2) * eh, k}
	end
	for i = 1, #bg_cols do
		spec[#spec+1] = ("box[%g,%g;%g,%g;%s]"):format(
			x, bg_cols[i][1], w, bg_cols[i][2], colours[bg_cols[i][3]])
	end
	for i = 1, #fg_cols do
		local colourized_image = minetest.formspec_escape(
			"mydev_vertgrad2.png^[multiply:" .. colours[fg_cols[i][2]])
		spec[#spec+1] = ("image[%g,%g;%g,%g;%s]"):format(
			x, fg_cols[i][1], w, 2.0 * eh, colourized_image)
	end
end

local function gradient_2d(x, y, w, h, colours, spec)
	local n = math.floor(math.sqrt(#colours))
	assert(#colours == n * n)
	assert(n % 2 == 1)
	local eh = h / (n - 1)
	local ew = w / (n - 1)
	local boxes = {}
	local vertgrads = {}
	local horgrads = {}
	local bothgrads = {}
	for col = 0, n-1 do
		local colours_off = col * n
		local bg_cols = {{y, eh, 1}}
		for k = 3, n-1, 2 do
			bg_cols[#bg_cols+1] = {y + (k - 2) * eh, 2.0 * eh, k}
		end
		bg_cols[#bg_cols+1] = {y + (n - 2) * eh, eh, n}
		local fg_cols = {{y, 2}}
		for k = 4, n, 2 do
			fg_cols[#fg_cols+1] = {y + (k - 2) * eh, k}
		end
		local col_x, col_w
		if col == 0 then
			col_x = x
			col_w = ew
		elseif col == n-1 then
			col_x = x + w - ew
			col_w = ew
		else
			col_x = x + ew * (col - 1)
			col_w = 2.0 * ew
		end
		if col % 2 == 0 then
			for i = 1, #bg_cols do
				boxes[#boxes+1] = ("box[%g,%g;%g,%g;%s]"):format(
					col_x, bg_cols[i][1], col_w, bg_cols[i][2],
					colours[colours_off + bg_cols[i][3]])
			end
			for i = 1, #fg_cols do
				local colourized_image = minetest.formspec_escape(
					"mydev_vertgrad.png^[multiply:" ..
					colours[colours_off + fg_cols[i][2]])
				vertgrads[#vertgrads+1] = ("image[%g,%g;%g,%g;%s]"):format(
					col_x, fg_cols[i][1], col_w, 2.0 * eh, colourized_image)
			end
		else
			for i = 1, #bg_cols do
				local colourized_image = minetest.formspec_escape(
					"mydev_horgrad.png^[multiply:" ..
					colours[colours_off + bg_cols[i][3]])
				horgrads[#horgrads+1] = ("image[%g,%g;%g,%g;%s]"):format(
					col_x, bg_cols[i][1], col_w, bg_cols[i][2],
					colourized_image)
			end
			for i = 1, #fg_cols do
				local colourized_image = minetest.formspec_escape(
					"mydev_bothgrad.png^[multiply:" ..
					colours[colours_off + fg_cols[i][2]])
				bothgrads[#bothgrads+1] = ("image[%g,%g;%g,%g;%s]"):format(
					col_x, fg_cols[i][1], col_w, 2.0 * eh, colourized_image)
			end
		end
	end
	local ordered_elementss = {boxes, vertgrads, horgrads, bothgrads}
	for k = 1, #ordered_elementss do
		local arr = ordered_elementss[k]
		for i = 1, #arr do
			spec[#spec+1] = arr[i]
		end
	end
end

local function get_gradient_2d_colours(func, res)
	local colours = {}
	for x = 0, res-1 do
		for y = 0, res-1 do
			colours[#colours+1] = func(x / (res - 1), y / (res - 1))
		end
	end
	return colours
end

local function linear_to_srgb(channel)
	if channel <= 0.0031308 then
		return 12.92 * channel
	else
		return (1.0 + 0.055) * channel ^ (1.0 / 2.4) - 0.055
	end
end

local function srgb_discretize(x)
	return math.min(math.max(math.floor(x * 255.0 + 0.5), 0), 255)
end

local function mycolour(x, y)
	local v1 = srgb_discretize(linear_to_srgb(x ^ 3))
	local v2 = srgb_discretize(linear_to_srgb(y ^ 3))
	local v3 = srgb_discretize(1.0 - x * y)
	local col = {r = v1, g = v2, b = v3, a = 255}
	return minetest.colorspec_to_colorstring(col)
end

local function get_spec()
	local spec = {"formspec_version[4]size[8,8]"}
	local x = 1
	local y = 1
	local w = 6
	local h = 6
	--~ local N = 31
	local colours = get_gradient_2d_colours(mycolour, 25)
	gradient_2d(x, y, w, h, colours, spec)
	--~ vertical_gradient(x, y, w, h, colours, spec)
	--~ spec[#spec+1] = ("box[%g,%g;%g,%g;#00FF00FF]"):format(x, y, w, h)
	--~ make_barfield(x, y, w, h, 30, "M", spec)
	--~ spec[#spec+1] = ("background[%g,%g;%g,%g;default_cobble.png]"):format(x, y, w, h)
	--~ spec[#spec+1] = "style_type[table;font=mono]"
	--~ spec[#spec+1] = "tableoptions[background=#00008080]"
	--~ spec[#spec+1] = "tablecolumns[image,padding=0,0=default_stone.png,1=default_cobble.png]"
	--~ spec[#spec+1] = ("table[%g,%g;%g,%g;mytable;1,0,0,1]"):format(x, y, w, h)

	return table.concat(spec)
end

minetest.register_on_player_receive_fields(function(_, formname, fields)
	if formname ~= "mydev:formspec_test" then
		return
	end
	print(dump(fields))
end)

--[[
minetest.register_on_joinplayer(function(player)
	minetest.show_formspec(player:get_player_name(), "mydev:formspec_test", get_spec())
end)
--]]

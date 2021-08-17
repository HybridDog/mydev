local sample_ucbspline = mydev.spline_voxelizing.sample_ucbspline
local simple_vmanip = mydev.common.simple_vmanip

local function random_pos_border(pos1, pos2)
	local r1 = math.random() > 0.5 and 1.0 or 0.0
	local r2 = math.random()
	local r3 = math.random()
	local shuf = math.random(3)
	if shuf == 2 then
		r1, r2 = r2, r1
	elseif shuf == 3 then
		r1, r3 = r3, r1
	end
	shuf = math.random(2)
	if shuf == 2 then
		r2, r3 = r3, r2
	end
	return {
		x = r1 * pos1.x + (1 - r1) * pos2.x,
		y = r2 * pos1.y + (1 - r2) * pos2.y,
		z = r3 * pos1.z + (1 - r3) * pos2.z,
	}
end

-- FIXME: Make the cave generation work with mapgen:
-- * Maybe calculate B-Spline points for given points where the curve should
--   go through
-- * Decide on where the curves should lead to and how much randomness and
--   noise-like patterns should appear
-- * Find a practical use

-- A priority queue based on LightQueue from voxelalgorithms.cpp
local LightQueue = {}
setmetatable(LightQueue, {__call = function(_, max_light)
	assert(max_light == math.floor(max_light) and max_light >= 1)
	local lights = {}
	local num_lights = {}
	for i = 1, max_light do
		lights[i] = {}
		num_lights[i] = 0
	end
	local obj = {lights = lights, num_lights = num_lights,
		max_light = max_light}
	setmetatable(obj, LightQueue)
	return obj
end})
LightQueue.__index = {
	push = function(self, light, pos)
		local n = self.num_lights[light]+1
		self.lights[light][n] = pos
		self.num_lights[light] = n
	end,
	next = function(self)
		local light = self.max_light
		local n = self.num_lights[light]
		if n == 0 then
			if light <= 0 then
				return
			end
			self.max_light = light - 1
			return self:next()
		end
		self.num_lights[light] = n-1
		return light, self.lights[light][n]
	end,
}

local function vector_is_bounded(pos, size)
	return pos.x >= 0 and pos.y >= 0 and pos.z >= 0
		and pos.x <= size.x-1 and pos.y <= size.y-1 and pos.z <= size.z-1
end

local function get_neighbours(vi, ystride, zstride, num_vis)
	local neighbours = {vi - 1, vi + 1, vi - ystride, vi + ystride,
		vi - zstride, vi + zstride}
	-- Remove neighbours outside the boundaries if needed
	local n = 6
	if vi % ystride == 0 then
		neighbours[1] = -1
		n = n-1
	end
	if vi % ystride == ystride - 1 then
		neighbours[2] = -1
		n = n-1
	end
	if vi % zstride < ystride then
		neighbours[3] = -1
		n = n-1
	end
	if vi % zstride >= zstride - ystride then
		neighbours[4] = -1
		n = n-1
	end
	if vi < 0 then
		neighbours[5] = -1
		n = n-1
	end
	if vi >= num_vis then
		neighbours[6] = -1
		n = n-1
	end
	if n == 6 then
		-- likely
		return neighbours
	end
	local restricted_neighbours = {}
	for k = 1,6 do
		if neighbours[k] >= 0 then
			restricted_neighbours[#restricted_neighbours+1] = neighbours[k]
		end
	end
	return restricted_neighbours
end

-- Calculates a Distance Field for the Manhattan distances to the points.
-- pos1 and pos2 are the boundaries within which it should be accurate.
-- max_dist is the maximum distance considered.
local function get_manhattan_df(pos1, pos2, points, max_dist)
	-- Extend boundaries for points which are outside and nonetheless have a
	-- small distance to the inside
	local minp = vector.subtract(pos1, max_dist-1)
	local maxp = vector.add(pos2, max_dist-1)
	local size = vector.subtract(vector.add(maxp, 1), minp)
	local ystride = size.x
	local zstride = ystride * size.y
	-- Initialize the distance field
	local num_vis = size.x * size.y * size.z
	local df = {}
	for k = 0, num_vis - 1 do
		df[k] = max_dist
	end
	-- Add the points to the distance field and a priority queue
	local pq = LightQueue(max_dist)
	for k = 1, #points do
		-- Assume the initial distance is always 0; may be changed later with
		-- 4D splines
		local dist_point = 0
		local pos_rel = vector.round(vector.subtract(points[k], minp))
		if vector_is_bounded(pos_rel, size) then
			local vi = pos_rel.z * zstride + pos_rel.y * ystride + pos_rel.x
			if df[vi] > dist_point then
				-- No other point mapped to the same position yet.
				df[vi] = dist_point
				pq:push(max_dist - dist_point, vi)
			end
		end
	end
	-- Spread the distances
	local light, vi = pq:next()
	while light do
		local light_new = light - 1
		if light_new <= 0 then
			-- finished
			break
		end
		local neighs = get_neighbours(vi, ystride, zstride, num_vis)
		for k = 1, #neighs do
			local vi_new = neighs[k]
			local dist = max_dist - light_new
			if df[vi_new] > dist then
				df[vi_new] = dist
				pq:push(light_new, vi_new)
			end
		end
		light, vi = pq:next()
	end

	return df, minp, maxp
end

local function rotate_point(p)
	local sin45 = 1.0 / math.sqrt(2.0)
	local cos45 = sin45
	--~ local cos30 = math.sqrt(3.0) * 0.5
	--~ local sin30 = 0.5
	-- Rotate by 45 degrees around X
	local prx = {
		x = p.x,
		y = cos45 * p.y + sin45 * p.z,
		z = -sin45 * p.y + cos45 * p.z
		--~ y = cos30 * p.y + sin30 * p.z,
		--~ z = -sin30 * p.y + cos30 * p.z
	}
	-- Rotate by 45 degrees around Z
	return {
		x = cos45 * prx.x + sin45 * prx.y,
		y = -sin45 * prx.x + cos45 * prx.y,
		z = prx.z
	}
end

local function vector_extend_bounds(pos, minp, maxp)
	if pos.x < minp.x then
		minp.x = pos.x
	elseif pos.x > maxp.x then
		maxp.x = pos.x
	end
	if pos.y < minp.y then
		minp.y = pos.y
	elseif pos.y > maxp.y then
		maxp.y = pos.y
	end
	if pos.z < minp.z then
		minp.z = pos.z
	elseif pos.z > maxp.z then
		maxp.z = pos.z
	end
end

local function vector_ceil(pos)
	return {x = math.ceil(pos.x), y = math.ceil(pos.y), z = math.ceil(pos.z)}
end

local function get_rotated_manhattan_df(points, max_dist)
	-- Rotate the points; FIXME: Ignore points out of bounds
	local minp, maxp
	local points_r = {}
	for k = 1, #points do
		local pos_r = rotate_point(points[k])
		if not minp then
			minp = vector.new(pos_r)
			maxp = vector.new(pos_r)
		else
			vector_extend_bounds(pos_r, minp, maxp)
		end
		points_r[k] = pos_r
	end
	return get_manhattan_df(vector.floor(minp), vector_ceil(maxp), points_r,
		max_dist)
end

local function get_merged_df(pos1, pos2, points, max_dist)
	local df1, minp1, maxp1 = get_manhattan_df(pos1, pos2, points, max_dist)
	local df2, minp2, maxp2 = get_rotated_manhattan_df(points, max_dist)
	local area1 = VoxelArea:new{MinEdge = minp1, MaxEdge = maxp1}
	local area2 = VoxelArea:new{MinEdge = minp2, MaxEdge = maxp2}
	local area_main = VoxelArea:new{MinEdge = pos1, MaxEdge = pos2}
	local df_main = {}
	for z = pos1.z, pos2.z do
		for y = pos1.y, pos2.y do
			for x = pos1.x, pos2.x do
				local vi1 = area1:index(x, y, z)
				local dist1 = df1[vi1]
				-- FIXME: instead of rounding, it is possible to do some
				-- interpolation
				local pos_r = vector.round(rotate_point({x=x, y=y, z=z}))
				local dist2
				if area2:containsp(pos_r) then
					dist2 = df2[area2:indexp(pos_r)]
				else
					dist2 = max_dist
				end
				local vi_main = area_main:index(x, y, z)
				-- Choose the value of Manhattan distance or rotated
				-- Manhattan distance which is closest to Euclidean distance
				df_main[vi_main] = math.max(dist1, dist2)
			end
		end
	end
	return df_main
end

-- Weierstrass function code from https://github.com/slemonide/gen
local function do_ws_func(a, x)
	local n = math.pi * x / 16000
	local y = 0
	for k = 1,1000 do
		y = y + math.sin(k^a * n)/(k^a)
	end
	return 1000*y/math.pi
end

-- caching function
local ws_values = {}
local function get_ws_value(a, x)
	local v = ws_values[a]
	if v then
		v = v[x]
		if v then
			return v
		end
	else
		ws_values[a] = {}
		-- weak table, see https://www.lua.org/pil/17.1.html
		setmetatable(ws_values[a], {__mode = "kv"})
	end
	v = do_ws_func(a, x)
	ws_values[a][x] = v
	return v
end

-- testing function
local function df_nodes(pos1, pos2, points, max_dist)
	local df = get_merged_df(pos1, pos2, points, max_dist)
	local area = VoxelArea:new{MinEdge = pos1, MaxEdge = pos2}
	local nodes = {}
	for z = pos1.z, pos2.z do
		for y = pos1.y, pos2.y do
			for x = pos1.x, pos2.x do
				local sel = (math.floor(get_ws_value(2, x) +
					--~ get_ws_value(3, y) + get_ws_value(2, z) + 0.5) % 5) / 5
					get_ws_value(3, y) + get_ws_value(5, z) + 0.5) % 5) / 5
				local dist = df[area:index(x, y, z)]
				local distm = (max_dist-1) * (1 - sel * 0.7)
				if dist > distm then
					nodes[#nodes+1] = {{x=x, y=y, z=z}, "default:stone"}
				end
			end
		end
	end
	return nodes
end

worldedit.register_command("splc", {
	description = "Test for spline cave",
	privs = {worldedit=true},
	params = "",
	require_pos = 1,
	func = function(playername)
		local pos1 = worldedit.pos1[playername]
		local pos2 = vector.add(pos1, vector.new(80, 80, 80))
		local spline_points = {}
		for k = 1, 30 do
			spline_points[k] = random_pos_border(pos1, pos2)
		end
		for k = 1, 3 do
			spline_points[#spline_points+1] = spline_points[k]
		end
		local points = sample_ucbspline(spline_points, 0.5, 1.1)
		--[[
		-- Show the sampled points
		local nodes = {}
		for k = 1,#points do
			local pos = vector.round(points[k])
			nodes[k] = {pos, "default:brick"}
		end
		--]]
		local max_dist = 9
		local minp = vector.subtract(pos1, max_dist-1)
		local maxp = vector.add(pos2, max_dist-1)
		local nodes = df_nodes(minp, maxp, points, max_dist)
		simple_vmanip(nodes)

		return true
	end,
})



local hilbert_table_3d
do
	local function strreplace(str, a, b)
		if not str then
			return str
		end
		return str:gsub(a, "P"):gsub(b, a):gsub("P", b)
	end
	local function strrot(str, a, b, c, d)
		if not str then
			return str
		end
		return str:gsub(a, "P"):gsub(b, a):gsub(c, b):gsub(d, c):gsub("P", d)
	end
	local function onallstr(t, func)
		for i = 1, #t do
			t[i] = {func(t[i][1]), func(t[i][2]), t[i][3]}
		end
	end
	local function flipz(t)
		local t_new = {}
		for i = 1,4 do
			t_new[i] = t[4 + i]
			t_new[4 + i] = t[i]
		end
		for i = 1,4 do
			t_new[i] = t[4 + i]
			t_new[4 + i] = t[i]
		end
		onallstr(t_new, function(str)
			return strreplace(str, "b", "f")
		end)
		return t_new
	end
	local function flipx(t)
		local t_new = {}
		for i = 1, 4 do
			t_new[2 * i - 1] = t[2 * i]
			t_new[2 * i] = t[2 * i - 1]
		end
		onallstr(t_new, function(str)
			return strreplace(str, "r", "l")
		end)
		return t_new
	end
	local function flipy(t)
		local t_new = {}
		local perm = {3, 4, 1, 2, 7, 8, 5, 6}
		for i = 1, 8 do
			t_new[i] = t[perm[i]]
		end
		onallstr(t_new, function(str)
			return strreplace(str, "u", "d")
		end)
		return t_new
	end
	-- 90 degrees counterclockwise
	local function roty(t)
		local t_new = {}
		local perm = {5, 1, 7, 3, 6, 2, 8, 4}
		for i = 1, 8 do
			t_new[i] = t[perm[i]]
		end
		onallstr(t_new, function(str)
			return strrot(str, "l", "b", "r", "f")
		end)
		return t_new
	end
	local function rotx(t)
		local t_new = {}
		local perm = {3, 4, 7, 8, 1, 2, 5, 6}
		for i = 1, 8 do
			t_new[i] = t[perm[i]]
		end
		onallstr(t_new, function(str)
			return strrot(str, "f", "d", "b", "u")
		end)
		return t_new
	end

	hilbert_table_3d = {
		bru = {{"rub", "b", 0}, {"flu", "u", 3},
			{"rdf", nil, 7}, {"flu", "b", 4},
			{"ubr", "r", 1}, {"ubr", "f", 2}, {"dbl", "f", 6}, {"dbl", "l", 5}},
	}
	hilbert_table_3d.flu = flipx(flipz(hilbert_table_3d.bru))
	hilbert_table_3d.bld = flipx(flipy(hilbert_table_3d.bru))
	hilbert_table_3d.frd = flipz(flipy(hilbert_table_3d.bru))
	hilbert_table_3d.dbl = roty(rotx(hilbert_table_3d.bru))
	hilbert_table_3d.ubr = flipx(flipy(hilbert_table_3d.dbl))
	hilbert_table_3d.ufl = flipz(flipy(hilbert_table_3d.dbl))
	hilbert_table_3d.dfr = flipz(flipx(hilbert_table_3d.dbl))
	hilbert_table_3d.rub = rotx(roty(hilbert_table_3d.flu))
	hilbert_table_3d.rdf = flipy(flipz(hilbert_table_3d.rub))
	hilbert_table_3d.luf = flipx(flipz(hilbert_table_3d.rub))
	hilbert_table_3d.ldb = flipy(flipx(hilbert_table_3d.rub))
end
-- TODO: what about Minetest's left-handed coordinate system?

local function hilbert_3d_get_direction(component_prev, dir_prev, x, y, z,
		level)
	if level == 0 then
		return dir_prev
	end
	x = 2 * x
	y = 2 * y
	z = 2 * z
	local i = 0
	if x >= 1 then
		i = i + 1
		x = x - 1
	end
	if y >= 1 then
		i = i + 2
		y = y - 1
	end
	if z >= 1 then
		i = i + 4
		z = z - 1
	end
	local data = hilbert_table_3d[component_prev][i+1]
	return hilbert_3d_get_direction(data[1], data[2] or dir_prev,
		x, y, z, level-1)
end

local HilbertCurve3D = {}
setmetatable(HilbertCurve3D, {__call = function(_, size)
	local num_levels = math.ceil(math.log(size) / math.log(2))
	local obj = {
		num_levels = num_levels,
		directions_cache = {}
	}
	setmetatable(obj.directions_cache, {__mode = "kv"})
	setmetatable(obj, HilbertCurve3D)
	return obj
end})
HilbertCurve3D.__index = {
	-- Returns a direction ("r", "l", "u", "d", "b", "f") where the curve exits
	-- at (x, y, z).
	-- ("r", "l", "u", "d", "b", "f") stand for (+X, -X, +Y, -Y, +Z, -Z), i.e.
	-- (right, left, up, down, backwards, forwards)
	-- (x, y, z) should be in {0, 1, …, size-1}^3
	get_out_direction = function(self, x, y, z)
		local size = 2 ^ self.num_levels
		assert(x >= 0 and y >= 0 and z >= 0
			and x < size and y < size and z < size)
		local vi = (z * size + y) * size + x
		local dir = self.directions_cache[vi]
		if dir then
			return dir
		end
		-- I chose the first level of the curve to go bbrfublff
		dir = hilbert_3d_get_direction("bru", "b", x / size, y / size, z / size,
			self.num_levels)
		self.directions_cache[vi] = dir
		return dir
	end,

	-- Returns a direction where the curve enters and exits at (x, y, z).
	-- Entering means exiting from a neighbouring position
	get_in_and_out_direction = function(self, x, y, z)
		local size = 2 ^ self.num_levels
		local off = {l = {-1, 0, 0}, r = {1, 0, 0}, d = {0, -1, 0},
			u = {0, 1, 0}, f = {0, 0, -1}, b = {0, 0, 1}}
		local dir_out = self:get_out_direction(x, y, z)
		local opposites = {r = "l", l = "r", u = "d", d = "u", f = "b", b = "f"}
		for dir, vec in pairs(off) do
			if dir ~= dir_out then
				local xo = x + vec[1]
				local yo = y + vec[2]
				local zo = z + vec[3]
				if xo >= 0 and yo >= 0 and zo >= 0
						and xo < size and yo < size and zo < size then
					local dir_out_neigh = self:get_out_direction(xo, yo, zo)
					if dir_out_neigh == opposites[dir] then
						-- Found a point which leads to (x, y, z)
						return opposites[dir_out_neigh], dir_out
					end
				end
			end
		end
		-- TODO: this fails
		-- Rare edge case: the beginning of the curve
		--~ assert(x == 0 and y == 0 and z == 0, "Couldn't find in for (" .. x ..
			--~ ", " .. y .. ", " .. z .. ")")
		-- The first level of the curve goes back, […]
		-- -> the first input direction is front
		return "f", dir_out
	end,
}




-- A table which defines the Hilbert curve recursively. The rows are ordered
-- for offsets (x,y) in (0,0), (1,0), (0,1), (1,1) (if the offsets are unscaled)
local hilbert_table_2d = {
	ur = {{"ru", "u", 0}, {"ld", nil, 3}, {"ur", "r", 1}, {"ur", "d", 2}},
	ld = {{"ld", "r", 2}, {"ur", nil, 3}, {"ld", "d", 1}, {"dl", "l", 0}},
	dl = {{"dl", "u", 2}, {"dl", "l", 1}, {"ru", nil, 3}, {"ld", "d", 0}},
	ru = {{"ur", "r", 0}, {"ru", "u", 1}, {"dl", nil, 3}, {"ru", "l", 2}},
}

-- Returns the outgoing direction of the (approximated) hilbert curve.
-- (x, y) should lie within [0,1)^2 and level defines the number of valid bits
-- after the comma of x and y.
local function hilbert_2d_get_direction(component_prev, dir_prev, x, y, level)
	if level == 0 then
		return dir_prev
	end
	x = 2 * x
	y = 2 * y
	local i = 0
	if x >= 1 then
		i = i + 1
		x = x - 1
	end
	if y >= 1 then
		i = i + 2
		y = y - 1
	end
	local data = hilbert_table_2d[component_prev][i+1]
	return hilbert_2d_get_direction(data[1], data[2] or dir_prev,
		x, y, level-1)
end

local HilbertCurve2D = {}
setmetatable(HilbertCurve2D, {__call = function(_, size)
	local num_levels = math.ceil(math.log(size) / math.log(2))
	local obj = {
		num_levels = num_levels,
		directions_cache = {}
	}
	setmetatable(obj.directions_cache, {__mode = "kv"})
	setmetatable(obj, HilbertCurve2D)
	return obj
end})
HilbertCurve2D.__index = {
	-- Returns a direction ("r", "l", "u" or "d") where the curve exits
	-- at (x, y).
	-- (x, y) should be in {0, 1, …, size-1}^2
	get_out_direction = function(self, x, y)
		local size = 2 ^ self.num_levels
		assert(x >= 0 and y >= 0 and x < size and y < size)
		local vi = y * size + x
		local dir = self.directions_cache[vi]
		if dir then
			return dir
		end
		-- I chose the first level of the curve to go
		-- right, up, right, down, right
		dir = hilbert_2d_get_direction("ur", "r", x / size, y / size,
			self.num_levels)
		self.directions_cache[vi] = dir
		return dir
	end,

	-- Returns a direction ("r", "l", "u" or "d") where the curve enters
	-- and exits at (x, y).
	-- Entering means exiting from a neighbouring position
	get_in_and_out_direction = function(self, x, y)
		local size = 2 ^ self.num_levels
		local off = {l = {-1, 0}, r = {1, 0}, d = {0, -1}, u = {0, 1}}
		local dir_out = self:get_out_direction(x, y)
		local opposites = {r = "l", l = "r", u = "d", d = "u"}
		for dir, vec in pairs(off) do
			if dir ~= dir_out then
				local xo = x + vec[1]
				local yo = y + vec[2]
				if xo >= 0 and yo >= 0 and xo < size and yo < size then
					local dir_out_neigh = self:get_out_direction(xo, yo)
					if dir_out_neigh == opposites[dir] then
						-- Found a point which leads to (x, y)
						return opposites[dir_out_neigh], dir_out
					end
				end
			end
		end
		-- Rare edge case: the beginning of the curve
		assert(x == 0 and y == 0, "Couldn't find in for (" .. x .. ", " ..
			y .. ")")
		-- The first level of the curve goes right, […]
		-- -> the first input direction is left
		return "l", dir_out
	end,
}

-- a testing function for the hilbert 2d curve
--~ local function get_2d_hilbert_nodes(pos1, pos2)
	--~ local nodes = {}
	--~ local size = math.ceil(
		--~ math.max(pos2.x - pos1.x, pos2.y - pos1.y, pos2.z - pos1.z) / 3)
	--~ local hilb = HilbertCurve2D(size)
	--~ for i = 0, size-1 do
		--~ for j = 0, size-1 do
			--~ local dir_in, dir_out = hilb:get_in_and_out_direction(i, j)
			--~ local x = pos1.x + 3 * i
			--~ local z = pos1.z + 3 * j
			--~ nodes[#nodes+1] = {{x=x+1, y=pos1.y, z=z+1}, "default:mese"}
			--~ local off = {l = {-1, 0}, r = {1, 0}, d = {0, -1}, u = {0, 1}}
			--~ local vec_in = off[dir_in]
			--~ local vec_out = off[dir_out]
			--~ nodes[#nodes+1] = {{x=x+vec_in[1]+1, y=pos1.y, z=z+vec_in[2]+1},
				--~ "default:stone"}
			--~ nodes[#nodes+1] = {{x=x+vec_out[1]+1, y=pos1.y, z=z+vec_out[2]+1},
				--~ "default:cobble"}
		--~ end
	--~ end
	--~ return nodes
--~ end

-- a testing function for the hilbert 3d curve
local function get_3d_hilbert_nodes(pos1, pos2)
	local nodes = {}
	local size = math.ceil(
		math.max(pos2.x - pos1.x, pos2.y - pos1.y, pos2.z - pos1.z) / 3)
	local hilb = HilbertCurve3D(size)
	for i = 0, size-1 do
		for j = 0, size-1 do
			for k = 0, size-1 do
				local dir_in, dir_out = hilb:get_in_and_out_direction(i, j, k)
				local x = pos1.x + 3 * i
				local y = pos1.y + 3 * j
				local z = pos1.z + 3 * k
				nodes[#nodes+1] = {{x=x+1, y=y+1, z=z+1}, "default:mese"}
				local off = {l = {-1, 0, 0}, r = {1, 0, 0}, d = {0, -1, 0},
					u = {0, 1, 0}, f = {0, 0, -1}, b = {0, 0, 1}}
				local vec_in = off[dir_in]
				local vec_out = off[dir_out]
				nodes[#nodes+1] = {{x=x+vec_in[1]+1, y=y+vec_in[2]+1,
					z=z+vec_in[3]+1}, "default:stone"}
				nodes[#nodes+1] = {{x=x+vec_out[1]+1, y=y+vec_out[2]+1,
					z=z+vec_out[3]+1}, "default:cobble"}
			end
		end
	end
	return nodes
end

worldedit.register_command("hilb", {
	description = "Test for hilbert curve",
	privs = {worldedit=true},
	params = "",
	require_pos = 1,
	func = function(playername)
		local pos1 = worldedit.pos1[playername]
		local pos2 = vector.add(pos1, 3*4)
		local nodes = get_3d_hilbert_nodes(pos1, pos2)
		simple_vmanip(nodes)

		return true
	end,
})

local sample_ucbspline = mydev.spline_voxelizing.sample_ucbspline
local simple_vmanip = mydev.common.simple_vmanip

local function random_pos_border(pos1, pos2, rand)
	local r1 = rand() > 0.5 and 1.0 or 0.0
	local r2 = rand()
	local r3 = rand()
	local shuf = rand(3)
	if shuf == 2 then
		r1, r2 = r2, r1
	elseif shuf == 3 then
		r1, r3 = r3, r1
	end
	shuf = rand(2)
	if shuf == 2 then
		r2, r3 = r3, r2
	end
	return {
		x = r1 * pos1.x + (1 - r1) * pos2.x,
		y = r2 * pos1.y + (1 - r2) * pos2.y,
		z = r3 * pos1.z + (1 - r3) * pos2.z,
	}
end

-- FIXME:
-- * Improve performance (bottlenecks)
-- * Use a 4D spline, the fourth dimension is the thickness
-- * Improve spline curve behaviour on chunk boundaries
--   (defined by hilbert curve)
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
		if light <= 0 then
			return
		end
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
	if vi-1 % ystride == 0 then
		neighbours[1] = -1
		n = n-1
	end
	if (vi-1) % ystride == ystride - 1 then
		neighbours[2] = -1
		n = n-1
	end
	if (vi-1) % zstride < ystride then
		neighbours[3] = -1
		n = n-1
	end
	if (vi-1) % zstride >= zstride - ystride then
		neighbours[4] = -1
		n = n-1
	end
	if (vi-1) < zstride then
		neighbours[5] = -1
		n = n-1
	end
	if (vi-1) >= num_vis - zstride then
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
	for k = 1, num_vis do
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
			local vi = pos_rel.z * zstride + pos_rel.y * ystride + pos_rel.x + 1
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
	assert(#points >= 1, "get_merged_df called without points")
	local df1, minp1, maxp1 = get_manhattan_df(pos1, pos2, points, max_dist)
	local df2, minp2, maxp2 = get_rotated_manhattan_df(points, max_dist)
	local area1 = VoxelArea:new{MinEdge = minp1, MaxEdge = maxp1}
	local area2 = VoxelArea:new{MinEdge = minp2, MaxEdge = maxp2}
	assert(area2:containsp(vector.subtract(maxp2, 1)))
	assert(df2[area2:indexp(vector.subtract(maxp2, 1))])
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
					if not dist2 then
						print(dump(area2))
						print(dump(pos_r))
						print("index", area2:indexp(pos_r))
						print("maxp2", dump(maxp2))
						print("#df2", #df2)
					end
					assert(dist2, "Missing distance field entry")
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
			spline_points[k] = random_pos_border(pos1, pos2, math.random)
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

local function vector_inside(pos, minp, maxp)
	for _,i in pairs({"x", "y", "z"}) do
		if pos[i] < minp[i]
		or pos[i] > maxp[i] then
			return false
		end
	end
	return true
end


-- Removes all points outside the specified boundary
local function filter_points(points, minp, maxp)
	local out = {}
	for k = 1, #points do
		local pos = points[k]
		if vector_inside(pos, minp, maxp) then
			out[#out+1] = pos
		end
	end
	return out
end

-- Returns a boundary point between two chunks where the cave can go through
local function direction_to_point(pos1, pos2, dir)
	local mid = vector.floor(vector.multiply(vector.add(pos1, pos2), 0.5))
	if dir == "l" then
		mid.x = pos1.x
	elseif dir == "r" then
		mid.x = pos2.x
	elseif dir == "d" then
		mid.y = pos1.y
	elseif dir == "u" then
		mid.y = pos2.y
	elseif dir == "b" then
		mid.z = pos2.z
	elseif dir == "f" then
		mid.z = pos1.z
	end
	return mid
end

-- Returns a random number generator seeded for the chunk
local function get_chunk_random(cx, cy, cz)
	local vi = 2 ^ 32 * cz + 2 ^ 16 * cy + cx
	local rand = PcgRandom(vi)
	return function(x)
		if x then
			return rand:next(1, x)
		end
		return rand:next(0, 2 ^ 16) / 2 ^ 16
	end
end

local cave_thickness = 10
local cave_thickness_min = 5
local basis_points_per_chunk = 3
local chunk_size = 171
-- Adds points of a B-Spline for this chunk
local function get_spline_points_in_chunk(cx, cy, cz, dir_in, dir_out)
	local rand = get_chunk_random(cx, cy, cz)
	local pos1 = vector.subtract(
		vector.multiply({x=cx, y=cy, z=cz}, chunk_size), 2 ^ 15)
	local pos2 = vector.add(pos1, chunk_size - 1)
	local pos_start = direction_to_point(pos1, pos2, dir_in)
	local pos_end = direction_to_point(pos1, pos2, dir_out)
	-- Take spline curve basis points inside this and the neighbouring chunks
	-- but ensure that the thick cave is always inside these chunks
	local minp = vector.subtract(pos1, chunk_size - cave_thickness)
	local maxp = vector.add(pos2, chunk_size - cave_thickness)
	-- Add three times the start and end points for now to ensure the curve
	-- is connected
	local points = {}
	points[#points+1] = pos_start
	points[#points+1] = pos_start
	points[#points+1] = pos_start
	for _ = 1, basis_points_per_chunk do
		points[#points+1] = random_pos_border(minp, maxp, rand)
	end
	points[#points+1] = pos_end
	points[#points+1] = pos_end
	points[#points+1] = pos_end
	return sample_ucbspline(points, 0.5, 1.1)
end


local hilb_global = mydev.HilbertCurve3D(2 ^ 16 / chunk_size)
local function get_cave_nodes(minp, maxp)
	local t = minetest.get_us_time()
	-- Collect points from spline curves for all chunks
	local p1 = vector.floor(vector.multiply(vector.add(minp, 2 ^ 15),
		1.0 / chunk_size))
	local p2 = vector_ceil(vector.multiply(vector.add(maxp, 2 ^ 15),
		1.0 / chunk_size))
	-- Add a slice of additional chunks on each side since the curves visit
	-- neighbouring chunks
	p1 = vector.subtract(p1, 1)
	p2 = vector.add(p2, 1)
	local points = {}
	for cz = p1.z, p2.z do
		for cy = p1.y, p2.y do
			for cx = p1.x, p2.x do
				local dir_in, dir_out =
					hilb_global:get_in_and_out_direction(cx, cy, cz)
				local pts = get_spline_points_in_chunk(cx, cy, cz, dir_in,
					dir_out)
				for k = 1, #pts do
					points[#points+1] = pts[k]
				end
			end
		end
	end
	-- Keep some points outside the boundary because of the thickness
	points = filter_points(points, vector.subtract(minp, cave_thickness),
		vector.add(maxp, cave_thickness))
	if #points == 0 then
		return {}
	end
	print(("spline points, %.5g"):format((minetest.get_us_time() - t) / 1000000))

	-- Calculate the distance field for the points and generate the cave
	-- additionally using the weierstrass function
	t = minetest.get_us_time()
	local df = get_merged_df(minp, maxp, points, cave_thickness+1)
	print(("df, %.5g"):format((minetest.get_us_time() - t) / 1000000))
	local area_df = VoxelArea:new{MinEdge = minp, MaxEdge = maxp}
	local nodes = {}
	for z = minp.z, maxp.z do
		for y = minp.y, maxp.y do
			for x = minp.x, maxp.x do
				local dist = df[area_df:index(x, y, z)]
				local sel = (math.floor(get_ws_value(2, x) +
					--~ get_ws_value(3, y) + get_ws_value(2, z) + 0.5) % 5) / 5
					get_ws_value(3, y) + get_ws_value(5, z) + 0.5) % 5) / 5
				local distm = cave_thickness_min
					+ (cave_thickness - cave_thickness_min) * sel
				if dist <= distm then
					nodes[#nodes+1] = {{x=x, y=y, z=z}, "default:cobble"}
				end
			end
		end
	end
	return nodes
end

-- a testing function for the hilbert 3d curve
local function get_3d_hilbert_nodes(pos1, pos2)
	local nodes = {}
	local size = math.ceil(
		math.max(pos2.x - pos1.x, pos2.y - pos1.y, pos2.z - pos1.z) / 3)
	local hilb = mydev.HilbertCurve3D(size)
	for i = 0, size-1 do
		for j = size-1, 0, -1 do
			for k = 0, size-1 do
				local dir_in, dir_out = hilb:get_in_and_out_direction(i, j, k)
				local x = pos1.x + 3 * i
				local y = pos1.y + 3 * j
				local z = pos1.z + 3 * k
				--~ nodes[#nodes+1] = {{x=x+1, y=y+1, z=z+1}, "default:mese"}
				nodes[#nodes+1] = {{x=x+1, y=y+1, z=z+1}, "default:stone"}
				local off = {l = {-1, 0, 0}, r = {1, 0, 0}, d = {0, -1, 0},
					u = {0, 1, 0}, f = {0, 0, -1}, b = {0, 0, 1}}
				local vec_in = off[dir_in]
				local vec_out = off[dir_out]
				if vec_in then
					nodes[#nodes+1] = {{x=x+vec_in[1]+1, y=y+vec_in[2]+1,
						z=z+vec_in[3]+1}, "default:stone"}
				end
				if vec_out then
					nodes[#nodes+1] = {{x=x+vec_out[1]+1, y=y+vec_out[2]+1,
						--~ z=z+vec_out[3]+1}, "default:cobble"}
						z=z+vec_out[3]+1}, "default:stone"}
				end
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
		local pos2 = vector.add(pos1, 3*16)
		local nodes = get_3d_hilbert_nodes(pos1, pos2)
		simple_vmanip(nodes)

		return true
	end,
})

--[[
worldedit.register_command("hilbgen", {
	description = "Test for hilbert curve",
	privs = {worldedit=true},
	params = "",
	require_pos = 1,
	func = function(playername)
		local minp = worldedit.pos1[playername]
		local maxp = vector.add(minp, 30)
		local points = get_spline_points(minp, maxp)
		for k = 1, #points do
			local pos = points[k]
			assert(pos.x >= minp.x and pos.x <= maxp.x and pos.y >= minp.y and pos.y <= maxp.y)
			minetest.set_node(pos, {name="default:mese"})
		end

		return true
	end,
})--]]

--[[
minetest.register_on_generated(function(minp, maxp)
	local t = minetest.get_us_time()
	local nodes = get_cave_nodes(minp, maxp)
	print(("nodes calculated, %.5g"):format((minetest.get_us_time() - t) / 1000000))
	t = minetest.get_us_time()
	simple_vmanip(nodes)
	print(("simple vmanip, %.5g"):format((minetest.get_us_time() - t) / 1000000))
end)
--]]

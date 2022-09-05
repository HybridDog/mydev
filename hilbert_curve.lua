
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
	local function rotx(t)
		local t_new = {}
		local perm = {3, 4, 7, 8, 1, 2, 5, 6}
		for i = 1, 8 do
			t_new[i] = t[perm[i]]
		end
		onallstr(t_new, function(str)
			return strrot(str, "b", "d", "f", "u")
		end)
		return t_new
	end
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
	hilbert_table_3d = {
		bru = {{"rub", "b", 0}, {"flu", "u", 3},
			{"rdf", nil, 7}, {"flu", "b", 4},
			{"ubr", "r", 1}, {"ubr", "f", 2}, {"dbl", "f", 6}, {"dbl", "l", 5}},
	}
	hilbert_table_3d.flu = flipx(flipz(hilbert_table_3d.bru))
	hilbert_table_3d.bld = flipx(flipy(hilbert_table_3d.bru))
	hilbert_table_3d.frd = flipz(flipy(hilbert_table_3d.bru))
	-- bru -> rotx -> urf -> roty -> ubr
	hilbert_table_3d.ubr = roty(rotx(hilbert_table_3d.bru))
	hilbert_table_3d.dbl = flipy(flipx(hilbert_table_3d.ubr))
	hilbert_table_3d.ufl = flipz(flipx(hilbert_table_3d.ubr))
	hilbert_table_3d.dfr = flipz(flipy(hilbert_table_3d.ubr))
	-- bru -> roty -> lbu -> rotx -> luf
	hilbert_table_3d.luf = rotx(roty(hilbert_table_3d.bru))
	hilbert_table_3d.rub = flipz(flipx(hilbert_table_3d.luf))
	hilbert_table_3d.rdf = flipy(flipx(hilbert_table_3d.luf))
	hilbert_table_3d.ldb = flipz(flipy(hilbert_table_3d.luf))
end

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
		dir = hilbert_3d_get_direction("bru", "f", x / size, y / size, z / size,
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
		-- Rare edge case: the beginning of the curve
		assert(x == 0 and y == 0 and z == 0, "Couldn't find in for (" .. x ..
			", " .. y .. ", " .. z .. ")")
		-- The first level of the curve goes back, […]
		-- -> the first input direction is front
		return "f", dir_out
	end,
}

-- A helper function to to along a direction
function HilbertCurve3D.go_in_direction(x, y, z, dir)
	local offsets = {
		l = {-1, 0, 0},
		r = {1, 0, 0},
		d = {0, -1, 0},
		u = {0, 1, 0},
		b = {0, 0, -1},
		f = {0, 0, 1},
	}
	local o = offsets[dir]
	return x + o[1], y + o[2], z + o[3]
end

-- Get the centre position of the cuboid face along direction dir.
-- pos1 and pos2 define the sorted cuboid boundary positions.
function HilbertCurve3D.centre_of_face(pos1, pos2, dir)
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

return HilbertCurve3D

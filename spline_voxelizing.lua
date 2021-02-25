local spline_voxelizing = {}

-- Returns the coefficients for a uniform cubic basis spline
-- t should be in [0, 1]
local function segment_factors(t)
	return {(1.0 - t)^3 / 6.0, (3.0 * t^3 - 6.0 * t^2 + 4.0) / 6.0,
		(-3.0 * t^3 + 3.0 * t^2 + 3.0 * t + 1.0) / 6.0,  t^3 / 6.0}
end

-- Evaluates the position for a uniform cubic basis spline segment
local function eval_segment(ps, t)
	local factors = segment_factors(t)
	local pos = {x = 0.0, y = 0.0, z = 0.0}
	for k = 1, 4 do
		pos.x = pos.x + ps[k].x * factors[k]
		pos.y = pos.y + ps[k].y * factors[k]
		pos.z = pos.z + ps[k].z * factors[k]
	end
	return pos
end

-- Evaluates the position for a given time in a uniform cubic basis spline
local function eval_spline(ps, t)
	local i = math.floor(t)
	assert(i >= 0 and i <= #ps - 4,
		"Invalid time for the given number of positions")
	local t_rel = t - i
	local ps_segment = {ps[i+1], ps[i+2], ps[i+3], ps[i+4]}
	return eval_segment(ps_segment, t_rel)
end

local function eval_spline_round(ps, t)
	return vector.round(eval_spline(ps, t))
end

-- Calculates the L infinity distance between two vectors
local function vector_maxdist(pos1, pos2)
	local diff = vector.subtract(pos2, pos1)
	return math.max(math.abs(diff.x), math.abs(diff.y), math.abs(diff.z))
end

-- An iterator for integer positions of an uniform cubic basis spline
function spline_voxelizing.iter_ucbspline(ps)
	local step = 0.1
	local n_current = {t_min = 0.0, t_max = 0.0,
		pos = eval_spline_round(ps, 0.0), n_next = nil}
	local first_invocation = true
	return function()
		if first_invocation then
			first_invocation = false
			return vector.new(n_current.pos), 0.0
		end
		if not n_current.n_next then
			-- Find some successor point which has a non-zero integer distance
			-- to the current point
			local t = n_current.t_max
			local pos
			while true do
				t = t + step
				local reached_end = t >= #ps - 3
				if reached_end then
					-- Reached the end of the spline, so try the latest point
					t = #ps - 4 + 0.9999
				end
				pos = eval_spline_round(ps, t)
				local dist = vector_maxdist(n_current.pos, pos)
				if dist > 0 then
					if dist <= 1 then
						-- Found a good next point, so no binary search is
						-- needed
						n_current = {t_min = t, t_max = t, pos = pos,
							n_next = nil}
						return vector.new(n_current.pos)
					end
					break
				elseif reached_end then
					return nil
				end
				n_current.t_max = t
			end
			n_current.n_next = {t_min = t, t_max = t, pos = pos,
				n_next = nil}
		end
		-- Return the next point if previous binary searches found a distance
		-- of 1
		if n_current.dist_to_next and n_current.dist_to_next == 1 then
			n_current = n_current.n_next
			return vector.new(n_current.pos)
		end
		-- Do binary search to find the next position with a sufficiently small
		-- distance to the current position
		while true do
			local n_next = n_current.n_next
			local t = 0.5 * (n_current.t_max + n_next.t_min)
			local pos = eval_spline_round(ps, t)
			local dist1 = vector_maxdist(n_current.pos, pos)
			local dist2 = vector_maxdist(n_next.pos, pos)
			if dist1 == 1 then
				-- Found a good position
				n_current.t_min = t
				n_current.t_max = t
				n_current.pos = pos
				n_current.dist_to_next = dist2
				-- dist2 cannot be zero:
				-- dist1 + dist2 >= dist(n_current.pos, n_next.pos) >= 2
				return vector.new(pos)
			elseif dist1 == 0 then
				-- Too close to the current position
				n_current.t_max = t
			else
				-- Too far from the current position
				if dist2 == 0 then
					-- Did not escape the next position
					n_next.t_min = t
				else
					-- Add a new point
					local n_new = {t_min = t, t_max = t, pos = pos,
						n_next = n_next, dist_to_next = dist2}
					n_current.n_next = n_new
				end
			end
		end
	end
end

local pos_to_int = minetest.hash_node_position
local int_to_pos = minetest.get_position_from_hash

-- Calculates positions for a surface defined by two splies
function spline_voxelizing.spline_triangles(ps1, ps2)
	assert(#ps1 == #ps2)
	local points_1 = {}
	local points_2 = {}
	local step = 0.1
	for t = 0.0, #ps1 - 4.0 + (1.0 - step), step do
		points_1[#points_1+1] = eval_spline(ps1, t)
		points_2[#points_2+1] = eval_spline(ps2, t)
	end
	local occupancy = {}
	for k = 1, #points_1-1 do
		local samples, n = vector.triangle(points_1[k], points_2[k],
			points_2[k+1])
		for i = 1, n do
			occupancy[pos_to_int(samples[i])] = true
		end
		samples, n = vector.triangle(points_1[k], points_2[k+1],
			points_1[k+1])
		for i = 1, n do
			occupancy[pos_to_int(samples[i])] = true
		end
	end
	local result = {}
	for vi in pairs(occupancy) do
		result[#result+1] = int_to_pos(vi)
	end
	return result, occupancy
end

return spline_voxelizing

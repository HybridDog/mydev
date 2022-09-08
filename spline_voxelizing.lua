-- Helper functions

-- Helper function to calculate the roots of a x^2 + b x + c
-- Algorithm taken from https://t1p.de/9g1sz
local function solve_quadratic(a, b, c)
	local discr = b * b - 4 * a * c
	if discr < 0 then
		-- Only complex solutions, so return no values
		return {}
	end
	if discr == 0 then
		return {-0.5 * b / a}
	end
	local q = b > 0 and
		-0.5 * (b + math.sqrt(discr)) or
		-0.5 * (b - math.sqrt(discr))
	local x1 = q / a
	local x2 = c / q
	-- Return the numbers in a sorted way
	if x1 > x2 then
		return {x2, x1}
	end
	return {x1, x2}
end

-- Calculates the L infinity distance between two vectors
local function vector_maxdist(pos1, pos2)
	local diff = vector.subtract(pos2, pos1)
	return math.max(math.abs(diff.x), math.abs(diff.y), math.abs(diff.z))
end

-- Tests if the cuboid defined by p2 is inside p1, outside p1 or cuts it
-- -1 means outside, 1 means inside, 0 means cut
local function cuboid_relation(p11, p12, p21, p22)
	p11, p12 = vector.sort(p11, p12)
	p21, p22 = vector.sort(p21, p22)
	if p12.x <= p21.x or p12.y <= p21.y or p12.z <= p21.z
	or p22.x <= p11.x or p22.y <= p11.y or p22.z <= p11.z then
		-- p1 and p2 are disjoint
		return -1
	end
	if p21.x >= p11.x and p21.y >= p11.y and p21.z >= p11.z
	and p22.x <= p12.x and p22.y <= p12.y and p22.z <= p12.z then
		-- p2 is a subset of p1
		return 1
	end
	-- p1 and p2 intersect and part of p2 is outside of p1
	return 0
end

-- Tests if a point is inside a cuboid
local function vector_inside(pos, minp, maxp)
	for _,i in pairs({"x", "y", "z"}) do
		if pos[i] < minp[i]
		or pos[i] > maxp[i] then
			return false
		end
	end
	return true
end


-- Spline curve related code

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

-- Finds all time values where the curve changes its monotonicity in any of
-- its dimensions. The start and end time are also added.
local function component_wise_critical_points(ps)
	local etimes = {0.0}
	-- Iterate over all segments
	for i = 0, #ps - 4 do
		for dim = 1, 3 do
			dim = ({"x", "y", "z"})[dim]
			-- Calculate extrema for the current segment and dimension
			local p = {ps[i+1][dim], ps[i+2][dim], ps[i+3][dim], ps[i+4][dim]}
			local a = -p[1] + 3.0 * p[2] - 3.0 * p[3] + p[4]
			local b = 2.0 * p[1] - 4.0 * p[2] + 2.0 * p[3]
			local c = -p[1] + p[3]
			local roots = solve_quadratic(a, b, c)
			-- Add extrema which are inside the segment to etimes
			for k = 1, #roots do
				local x = roots[k]
				-- FIXME: is the [0,1] interval check numerically accurate here?
				if x >= 0.0 and x <= 1.0 then
					-- Add the extremum wrt the whole curve to the list
					etimes[#etimes+1] = i + x
				end
			end
		end
	end
	etimes[#etimes+1] = #ps - 4.0 + 0.9999
	-- Sort and remove duplicates
	table.sort(etimes)
	local etimes_uniq = {etimes[1]}
	for i = 2, #etimes do
		if etimes[i] ~= etimes_uniq[#etimes_uniq] then
			etimes_uniq[#etimes_uniq+1] = etimes[i]
		end
	end
	if etimes_uniq[#etimes_uniq] > #ps - 4.0 + 0.9999 then
		etimes_uniq[#etimes_uniq] = nil
	end
	return etimes_uniq
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

-- A simple function to calculate floating point positions of an uniform cubic
-- basis spline.
-- Two successive points will have a distance in [dist_min, dist_max].
-- ps are the basis points; the curve is sampled for time values in
-- [t_start, t_end].
-- The points will be added to the positions table.
local function sample_ucbspline_at(ps, dist_min, dist_max, t_start, t_end,
		positions)
	assert(0 < dist_min and dist_min < dist_max)
	assert(t_start <= t_end)
	local t = t_start
	local t_delta = 0.1
	local pos = eval_spline(ps, t_start)
	positions[#positions+1] = pos
	while true do
		local t_next = t + t_delta
		local pos_next = eval_spline(ps, math.min(t_next, t_end))
		local dist = vector.length(vector.subtract(pos, pos_next))
		if dist < dist_min then
			if t_next > t_end then
				-- Time exceeded although distance is small -> finished
				break
			end
			-- Distance too small, try again with a bigger time
			t_delta = t_delta * 1.5
		elseif dist > dist_max then
			-- Distance too big, try again with a smaller time
			t_delta = t_delta * 0.5
		else
			-- Found a valid point
			positions[#positions+1] = pos_next
			t = t_next
			pos = pos_next
		end
	end
end

-- A simple function to calculate floating point positions of an uniform cubic
-- basis spline.
-- Two successive points have a distance in [dist_min, dist_max].
function spline_voxelizing.sample_ucbspline(ps, dist_min, dist_max)
	local positions = {}
	local t_max = #ps - 4.0 + 0.9999
	sample_ucbspline_at(ps, dist_min, dist_max, 0.0, t_max, positions)
	return positions
end

-- Calculates a set of floating point positions of an uniform cubic basis spline
-- inside a cuboid.
-- Two points successive on the curve have a distance in [dist_min, dist_max]
-- if the curve does not leave the cuboid in between.
function spline_voxelizing.sample_ucbspline_in_cuboid(ps, dist_min, dist_max,
		minp, maxp)
	-- Determine time intervals where the curve is inside the cuboid from minp
	-- to maxp
	local ema = component_wise_critical_points(ps)
	-- Intervals where the curve is fully contained in the cuboid
	local intervals_inside = {}
	-- Intervals where its bounding cuboid cuts the cuboid defined by minp and
	-- maxp
	local intervals = {}
	-- Positions to avoid redundant reevaluations of the spline
	local intervals_p = {}
	local pos1 = eval_spline(ps, ema[1])
	for i = 1, #ema-1 do
		local t1 = ema[i]
		local t2 = ema[i+1]
		local pos2 = eval_spline(ps, t2)
		local r = cuboid_relation(minp, maxp, pos1, pos2)
		if r == 0 then
			intervals[#intervals+1] = {t1, t2}
			intervals_p[#intervals_p+1] = {pos1, pos2}
		elseif r == 1 then
			intervals_inside[#intervals_inside+1] = {t1, t2}
		end
		pos1 = pos2
	end

	-- Recursively divide intervals to reduce the overall number of redundant
	-- sample points later
	-- Intervals where its bounding cuboid cuts the cuboid defined by minp and
	-- maxp and which won't be further subdivided
	local intervals_nosplit = {}
	local split_length_tresh = dist_max * 10.0
	while #intervals > 0 do
		local intervals_next = {}
		local intervals_next_p = {}
		for i = 1, #intervals do
			local t1, t2 = intervals[i][1], intervals[i][2]
			local t_new = 0.5 * (t1 + t2)
			local pos_new = eval_spline(ps, t_new)
			local parts = {
				{{t1, t_new}, {intervals_p[i][1], pos_new}},
				{{t_new, t2}, {pos_new, intervals_p[i][2]}}
			}
			for k = 1,2 do
				local times = parts[k][1]
				local positions = parts[k][2]
				local r = cuboid_relation(minp, maxp, positions[1], positions[2])
				if r == 0 then
					if vector.distance(positions[1], positions[2])
							< split_length_tresh then
						-- No longer split this interval
						intervals_nosplit[#intervals_nosplit+1] = times
					else
						-- Split the interval in the next iteration
						intervals_next[#intervals_next+1] = times
						intervals_next_p[#intervals_next_p+1] = positions
					end
				elseif r == 1 then
					-- The curve at these times is fully inside the cuboid
					intervals_inside[#intervals_inside+1] = times
				end
			end
		end
		intervals = intervals_next
		intervals_p = intervals_next_p
	end

	-- Sample the curve in the intervals
	local positions = {}
	-- Positions completely inside the cuboid
	for i = 1, #intervals_inside do
		sample_ucbspline_at(ps, dist_min, dist_max, intervals_inside[i][1],
			intervals_inside[i][2], positions)
	end
	-- Positions partly inside the cuboid
	local positions_with_redundancy = {}
	for i = 1, #intervals_nosplit do
		sample_ucbspline_at(ps, dist_min, dist_max, intervals_nosplit[i][1],
			intervals_nosplit[i][2], positions_with_redundancy)
	end
	for i = 1, #positions_with_redundancy do
		local pos = positions_with_redundancy[i]
		if vector_inside(pos, minp, maxp) then
			positions[#positions+1] = pos
		end
	end
	return positions
end


local pos_to_int = minetest.hash_node_position
local int_to_pos = minetest.get_position_from_hash

-- Calculates positions for a surface defined by two splines
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

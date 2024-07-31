-- Attempt to implement the greedy algorithm to find tube positions from
-- https://forum.minetest.net/viewtopic.php?p=435795#p435795
-- There is no splines yet.

-- TODO: replace this dummy with an actual spline
local Kurve = {}
setmetatable(Kurve, {__call = function(_, pos1, pos2)
	local obj = {
		pos1 = pos1,
		pos2 = pos2
	}
	setmetatable(obj, Kurve)
	return obj
end})
Kurve.__index = {
	-- Given a position, find the curve parameter which leads to the closest
	-- position on the curve
	project_to_curve = function(self, pos)
		local v = self.pos2 - self.pos1
		return vector.dot(pos - self.pos1, v) / vector.dot(v, v)
	end,

	-- Given a position, find the closest position on the curve
	project_to_curve_pos = function(self, pos)
		local v = self.pos2 - self.pos1
		return self.pos1 + vector.dot(pos - self.pos1, v) / vector.dot(v, v) * v
	end,

	-- Determine the distance between pos and the closest point on the curve
	distance_to_curve = function(self, pos)
		return vector.length(pos - self:project_to_curve_pos(pos))
	end,

	-- Determine the tangent of the curve at the position defined by parameter t
	get_tangent = function(self, _)
		return vector.normalize(self.pos2 - self.pos1)
	end,

	-- Determine the start position of the curve
	get_start_pos = function(self)
		return self.pos1
	end,

	-- Given two positions p1 and p2, determine the angle between them with
	-- respect to the tangent at the closest point on the curve to p1.
	-- The angle grows clockwise, lies in [-pi, pi] and jumps from pi to -pi
	-- when p1 and p2 are on the opposite side of the curve.
	get_rotation = function(self, p1, p2)
		local tangent = vector.normalize(self.pos2 - self.pos1)
		local p1_on_curve = self:project_to_curve_pos(p1)
		local p2_on_curve = self:project_to_curve_pos(p2)
		local v1 = vector.normalize(p1 - p1_on_curve)
		local v2 = vector.normalize(p2 - p2_on_curve)
		local angle = math.acos(vector.dot(v1, v2))
		if vector.dot(vector.cross(v1, v2), tangent) < 0 then
			angle = -angle
		end
		return angle
	end,
}

-- Offset vectors for node face touching, edge touching (including face)
-- and corner touching (including edge and face)
local offsets_face = {}
--~ local offsets_edge = {}
local offsets_corner = {}
for z = -1, 1 do
	for y = -1, 1 do
		for x = -1, 1 do
			local dist_manhattan = math.abs(x) + math.abs(y) + math.abs(z)
			if dist_manhattan ~= 0 then
				local off = vector.new(x, y, z)
				offsets_corner[#offsets_corner+1] = off
				if dist_manhattan <= 2 then
					--~ offsets_edge[#offsets_edge+1] = off
					if dist_manhattan == 1 then
						offsets_face[#offsets_face+1] = off
					end
				end
			end
		end
	end
end

-- Pairs of offset vectors.
-- With these it is possible to check if a node at a position is visually
-- redundant if there are already nodes at the two positions offset by the
-- offset vectors in the pair.
--~ local diagonal_neighbour_pairs = {}
--~ for o = 1, #offsets_face do
	--~ local off = offsets_face[o]
	--~ for o2 = o+1, #offsets_face do
		--~ local off2 = offsets_face[o2]
		--~ local diff = off2 - off
		--~ if math.abs(diff.x) < 2
		--~ and math.abs(diff.y) < 2
		--~ and math.abs(diff.z) < 2 then
			--~ diagonal_neighbour_pairs[#diagonal_neighbour_pairs+1] = {off, off2}
		--~ end
	--~ end
--~ end

-- Check if pos is visually redundant according with the existing positions in
-- occupant_positions
local function adds_redundant_thickness(_, curve, radius, pos)
	for i = 1, #offsets_face do
		local dist_neighbour = curve:distance_to_curve(pos + offsets_face[i])
		if dist_neighbour < radius then
			return false
		end
	end
	return true
end
--~ local function adds_redundant_thickness(occupant_positions, curve, radius, pos)
	--~ for i = 1, #diagonal_neighbour_pairs do
		--~ local offs = diagonal_neighbour_pairs[i]
		--~ local vi1 = minetest.hash_node_position(pos + offs[1])
		--~ local vi2 = minetest.hash_node_position(pos + offs[2])
		--~ if occupant_positions[vi1] and occupant_positions[vi2] then
			--~ return true
		--~ end
	--~ end
	--~ return false
--~ end

-- Test which one of the scores is better.
-- positive: s2 is better
-- negative: s1 is better
-- 0: both scores are equal
local function compare_score(s1, s2)
	for i = 1, #s1 do
		local d = s2[i] - s1[i]
		if d ~= 0 then
			return d
		end
	end
	return 0
end

-- Determine how good a candidate fits as the next position in the greedy
-- sampling
local function get_score(curve, radius, occupant_positions, pos_prev, pos)
	local score1 = 0
	local travel_distance = curve:project_to_curve(pos)
	if travel_distance >= 0 then
		-- We must not go backwards away from the curve
		score1 = score1 + 16
	end
	local orthogonal_distance = curve:distance_to_curve(pos)
	if orthogonal_distance >= radius then
		-- We must not have a too small radius
		score1 = score1 + 8
	end
	if not adds_redundant_thickness(occupant_positions, curve, radius, pos) then
		-- pos does not add unnecessary thickness to the tube.
		-- This case ensures that the tube is as thin as possible and does not
		-- have a too large radius.
		score1 = score1 + 4
	end
	local vi = minetest.hash_node_position(pos)
	if not occupant_positions[vi] then
		-- pos is already in the collected list of tube positions.
		-- Add a score1 which may help to prevent an infinite loop.
		score1 = score1 + 2
	end
	local angle = curve:get_rotation(pos_prev, pos)
	if angle > 0 then
		-- pos does not follow the spiral in the wrong direction orthogonally to
		-- the linear spline.
		-- This case ensures that the position selection circles around and does
		-- not get stuck in local minima.
		score1 = score1 + 1
	end
	-- Prefer points which go less far when projected onto the curve.
	-- This ensures that the tube is as thick as needed and does not consist of
	-- a line.
	local score2 = -travel_distance
	--~ local travel_distance_prev = curve:project_to_curve(pos_prev)
	--~ local travel_distance_rel = travel_distance - travel_distance_prev
	--~ local score2 = -math.abs(travel_distance_rel)
	-- Prefer points which are close to the tube radius.
	-- This case steers the position selection to adhere to the tube radius.
	local score3 = -math.abs(orthogonal_distance - radius)
	-- Prefer points which follow the spiral more slowly.
	-- This case should only happen if there is a tie.
	local score4 = -angle
	return {score1, score2, score3, score4}
end

-- Get a starting position for the greedy tube voxelization
local function get_start_point(curve, radius)
	local tangent = curve:get_tangent(0)
	local some_vector = vector.new(tangent.y, tangent.x, tangent.z)
	return vector.round(curve:get_start_pos() +
		vector.normalize(vector.cross(tangent, some_vector)) * radius)
end

local function sample_tube(curve, radius)
	local ps = {}
	local ps_occ = {}
	local pos_current = get_start_point(curve, radius)
	ps[#ps+1] = pos_current
	ps_occ[minetest.hash_node_position(pos_current)] = true
	for _ = 1, 100000 do
		for i = 1, 4 * radius * radius do
			local score_best, pos_best
			for o = 1, #offsets_corner do
				local pos_candidate = pos_current + offsets_corner[o]
				local score_candidate = get_score(curve, radius, ps_occ,
					pos_current, pos_candidate)
				if not score_best
				or compare_score(score_best, score_candidate) > 0 then
					score_best = score_candidate
					pos_best = pos_candidate
				end
			end
			pos_current = pos_best
			local curve_length = 1
			local vi = minetest.hash_node_position(pos_current)
			if not ps_occ[vi]
			and curve:project_to_curve(pos_current) < curve_length then
				ps_occ[vi] = true
				ps[#ps+1] = pos_current
				--~ print(dump(pos_current), dump(score_best))
				break
			end
			if i == 4 * radius * radius then
				return ps, ps_occ
			end
		end
	end
	minetest.chat_send_all("no early termination!!!")
	return ps, ps_occ
end

worldedit.register_command("gst", {
	description = "Test for greedy spline tube",
	privs = {worldedit=true},
	params = "",
	require_pos = 2,
	func = function(playername)
		local pos1 = worldedit.pos1[playername]
		local pos2 = worldedit.pos2[playername]
		local curve = Kurve(pos1, pos2)

		local player = minetest.get_player_by_name(playername)
		if not player then
			return
		end
		--~ local ppos = player:get_pos()
		--~ local p1 = pos1 + vector.new(0,3,0)
		--~ minetest.set_node(p1, {name="default:stone"})
		--~ minetest.chat_send_all(curve:get_rotation(p1, ppos))
		--~ minetest.chat_send_all(curve:project_to_curve(ppos))
		--~ local pos = curve:project_to_curve_pos(ppos)
		--~ pos = vector.round(pos)
		--~ minetest.set_node(pos, {name="default:cobble"})
		local t0 = minetest.get_us_time()
		local ps, _ = sample_tube(curve, 6)
		minetest.chat_send_all(("sampled %d position after %.5g s"):format(#ps, (minetest.get_us_time() - t0) / 1000000))
		for i = 1, #ps do
			minetest.set_node(ps[i], {name="default:cobble"})
		end
		return true
	end,
})

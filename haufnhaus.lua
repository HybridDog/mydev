local common = mydev.common
local hash2 = common.hash2
local unhash2 = common.unhash2

-- Probability for shrinking the walls in one step given that the movement was
-- not straight upwards
local shrink_probability = 0.4
-- (Small integer) weights for choosing the straight upwards direction (+0),
-- going to the side (-x, +x, -z, +z), and diagonally (-x-z, +x-z, -x+z, +x+z)
local step_length_weights = {4 / 4, 2, 1}
-- Radius bounds for the initial wall
local rmin = 8
local rmax = 14

local function test()
	local hashes = {}
	for x = -1, 1 do
		for y = -1, 1 do
			local k = hash2(x, y)
			hashes[#hashes+1] = k
			local reverted = unhash2(k)
			assert(reverted[1] == x and reverted[2] == y)
		end
	end
--[[
	table.sort(hashes)
	for k = 1, #hashes do
		local vi = hashes[k]
		local p = unhash2(hashes[k])
		print(("vi: %g, x: %g, y: %g"):format(vi, p[1], p[2]))
	end
]]
end
test()

local offsets_neighbours = {-1, 1, -0x10000, 0x10000}

-- Test if a horizontal neighbour of vi is outside the building
local function is_boundary_position(offsets, vi)
	for i = 1, #offsets_neighbours do
		if not offsets[vi + offsets_neighbours[i]] then
			return true
		end
	end
	return false
end


local offset_steps = {}
do
	-- Calculate a table with offsets and repeat some of them to encode the
	-- probabilities
	for x = -1, 1 do
		for z = -1, 1 do
			local step_length = math.abs(x) + math.abs(z)
			for _ = 1, step_length_weights[step_length+1] do
				offset_steps[#offset_steps+1] = z * 0x10000 + x
			end
		end
	end
end

-- Calculate a new occupancy table for a given offset value and shrink boolean
local function get_next_occupancy(occupancy, offset, do_shrink)
	assert(not do_shrink or offset ~= 0)
	local result = {}
	-- Add all positions above occupancy's inner positions so that no holes can
	-- appear
	for vi, occ in pairs(occupancy) do
		if occ == 1 then
			result[vi] = 2
		end
	end
	if do_shrink then
		-- Offset the positions but always ensure that positions below them
		-- are occupied
		for vi in pairs(occupancy) do
			local vi_moved = vi + offset
			if occupancy[vi_moved] then
				result[vi_moved] = 2
			end
		end
	else
		-- Simply offset the positions
		for vi in pairs(occupancy) do
			result[vi + offset] = 2
		end
	end
	-- Recalculate the inner part
	for vi in pairs(result) do
		if occupancy[vi] and not is_boundary_position(result, vi) then
			result[vi] = 1
		end
	end
	return result
end

local function haufnhaus(pos)
	print("Generating a haufnhaus at " .. dump(pos))
	local fundament = common.get_perlin_field(rmin, rmax)
	local occupancy = {}
	for _, v in pairs(fundament) do
		occupancy[hash2(v[1], v[2])] = 1
	end
	for vi in pairs(occupancy) do
		if is_boundary_position(occupancy, vi) then
			occupancy[vi] = 2
		end
	end

	local occupancies = {occupancy, occupancy, occupancy, occupancy}
	local prand = math.random()
	for _ = 1, 245 do
		local offset = offset_steps[math.random(#offset_steps)]
		local do_shrink = offset ~= 0 and prand < shrink_probability
		prand = (prand + 0.6180339887) % 1.0
		occupancy = get_next_occupancy(occupancy, offset, do_shrink)
		if not next(occupancy) then
			break
		end
		occupancies[#occupancies+1] = occupancy
	end
	for i = 1, #occupancies do
		local inner_node = (i > 1 and i < #occupancies) and "air" or "default:stone"
		local wall_node = "default:dirt"
		for k, occ in pairs(occupancies[i]) do
			local v = unhash2(k)
			local node_name = occ == 1 and inner_node or wall_node
			minetest.set_node({x=pos.x + v[1], y = pos.y + i - 1, z = pos.z + v[2]},
				{name=node_name})
		end
	end
end

minetest.register_node("mydev:haufnhaus", {
	description = "Haufnhaus bauer",
	tiles = {"default_mineral_diamond.png"},
	light_source = 14,
	groups = {snappy=2, choppy=2, oddly_breakable_by_hand=1},
	sounds = default.node_sound_wood_defaults(),
	on_place = function(_,_, pt)
		haufnhaus(pt.above)
	end,
})

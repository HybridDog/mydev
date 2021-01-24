local iter_spline = mydev.spline_voxelizing.iter_ucbspline

--[[
--~ local gold = 0.5 * math.sqrt(5.0) - 0.5
local function random_pos(pos1, pos2)
	local r1 = math.random()
	local r2 = math.random()
	local r3 = math.random()
	--~ local r2 = (r1 + gold) % 1.0
	--~ local r3 = (r2 + gold) % 1.0
	return {
		x = r1 * pos1.x + (1 - r1) * pos2.x,
		y = r2 * pos1.y + (1 - r2) * pos2.y,
		z = r3 * pos1.z + (1 - r3) * pos2.z,
	}
end
--]]

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

worldedit.register_command("spli", {
	description = "Test for spline voxelization",
	privs = {worldedit=true},
	params = "",
	require_pos = 1,
	func = function(playername)
		local pos1 = worldedit.pos1[playername]
		local pos2 = vector.add(pos1, vector.new(80, 80, 80))
		local spline_points = {}
		for k = 1, 300 do
			spline_points[k] = random_pos_border(pos1, pos2)
		end
		for k = 1, 3 do
			spline_points[#spline_points+1] = spline_points[k]
		end
		for pos in iter_spline(spline_points) do
			minetest.set_node(pos, {name="default:brick"})
		end

		return true
	end,
})

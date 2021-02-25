local path = minetest.get_modpath("mydev")
local datastructures = dofile(path .. "/datastructures.lua")
local common = dofile(path .. "/common.lua")
local spline_voxelizing = dofile(path .. "/spline_voxelizing.lua")

mydev = {common = common, datastructures = datastructures,
	spline_voxelizing = spline_voxelizing}
mydev.fill_sf = dofile(path .. "/fill_sf.lua")
dofile(path .. "/haufnhaus.lua")
dofile(path .. "/burgr.lua")
dofile(path .. "/trianglesphere.lua")
dofile(path .. "/splinetests.lua")


-----------------------  -------------------------------------------------------

-- Testing code for pseudo emissive mapping
minetest.register_node("mydev:emisstest", {
	description = "Fullbright Source",
	tiles = {"default_mineral_diamond.png"},
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			{-0.51, -0.51, -0.51, 0.51, 2.51, 0.51},
		}
	},
	light_source = 14,
	groups = {snappy=2, choppy=2, oddly_breakable_by_hand=1},
	sounds = default.node_sound_wood_defaults(),
})


-----------------------  -------------------------------------------------------


--~ minetest.override_item("default:wood", {
	--~ after_place_node = function(pos)
		--~ for i = 1,1000 do
			--~ minetest.set_node(pos, {name="default:wood"})
			--~ minetest.remove_node(pos)
		--~ end
	--~ end
--~ })

--[[
-- Test code for node placement and dig predictions
minetest.override_item("default:wood", {
	tiles = {"default_wood.png", "default_brick.png"},
	node_placement_prediction = "default:stone",
	node_dig_prediction = "default:cobble",
	can_dig = function() return false end,
	--~ on_place = function(_,_, pt)
		--~ minetest.set_node(pt.under, {name="default:mese"})
	--~ end,
})
]]

--~ minetest.register_chatcommand("a", {
    --~ func = function(name)
        --~ minetest.show_formspec(name, "a", [[
            --~ size[4,4]
            --~ bgcolor[red]
            --~ label[1,1;hi]
        --~ ]])
    --~ end,
--~ })

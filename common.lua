local funcs = {}

function funcs.hash2(x, y)
	return (y + 0x8000) * 0x10000 + x + 0x8000
end

function funcs.unhash2(k)
	local r = k % 0x10000
	return {r - 0x8000, (k - r) / 0x10000 - 0x8000}
end


-- returns a perlin chunk field of positions
local default_nparams = {
   offset = 0,
   scale = 1,
   seed = 3337,
   octaves = 6,
   persist = 0.6
}
function funcs.get_perlin_field(rmin, rmax, nparams)
	local r = math.ceil(rmax)
	nparams = nparams or {}
	for i,v in pairs(default_nparams) do
		nparams[i] = nparams[i] or v
	end
	nparams.spread = nparams.spread or vector.from_number(r*5)

	local pos = {x=math.random(-30000, 30000), y=math.random(-30000, 30000)}
	local map = minetest.get_perlin_map(
		nparams,
		vector.from_number(r+r+1)
	):get2dMap_flat(pos)

	local id = 1

	local bare_maxdist = rmax*rmax
	local bare_mindist = rmin*rmin

	local mindist = math.sqrt(bare_mindist)
	local dist_diff = math.sqrt(bare_maxdist)-mindist
	mindist = mindist/dist_diff

	local pval_min, pval_max

	local tab, n = {}, 1
	for z=-r,r do
		local zz = z*z
		for x=-r,r do
			local bare_dist = zz+x*x
			local add = bare_dist < bare_mindist
			local pval, distdiv
			if not add
			and bare_dist <= bare_maxdist then
				distdiv = math.sqrt(bare_dist)/dist_diff-mindist
				pval = math.abs(map[id]) -- fix values > 1
				if not pval_min then
					pval_min = pval
					pval_max = pval
				else
					pval_min = math.min(pval, pval_min)
					pval_max = math.max(pval, pval_max)
				end
				add = true--distdiv < 1-math.abs(map[id])
			end

			if add then
				tab[n] = {x,z, pval, distdiv}
				n = n+1
			end
			id = id+1
		end
	end

	-- change strange values
	local pval_diff = pval_max - pval_min
	pval_min = pval_min/pval_diff

	for k,i in pairs(tab) do
		if i[3] then
			local new_pval = math.abs(i[3]/pval_diff - pval_min)
			if i[4] < new_pval then
				tab[k] = {i[1], i[2]}
			else
				tab[k] = nil
			end
		end
	end
	return tab
end


-- A simple function to set nodes with vmanip instead of set_node
-- Nodes is a list, for example {{{x=0, y=1, z=2}, "default:cobble"}}
function funcs.simple_vmanip(nodes)
	local num_nodes = #nodes
	if num_nodes == 0 then
		return
	end
	local minp = vector.new(nodes[1][1])
	local maxp = vector.new(minp)
	for i = 1, num_nodes do
		local pos = nodes[i][1]
		local coords = {"x", "y", "z"}
		for k = 1, 3 do
			local c = coords[k]
			if pos[c] < minp[c] then
				minp[c] = pos[c]
			elseif pos[c] > maxp[c] then
				maxp[c] = pos[c]
			end
		end
	end

	local manip = minetest.get_voxel_manip()
	local e1, e2 = manip:read_from_map(minp, maxp)
	local area = VoxelArea:new{MinEdge=e1, MaxEdge=e2}
	local data = manip:get_data()

	local ids = {}
	for i = 1, num_nodes do
		local vi = area:indexp(nodes[i][1])
		local nodename = nodes[i][2]
		ids[nodename] = ids[nodename] or minetest.get_content_id(nodename)
		data[vi] = ids[nodename]
	end

	manip:set_data(data)
	manip:write_to_map()
end


return funcs

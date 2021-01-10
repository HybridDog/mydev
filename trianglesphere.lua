local datastructures = mydev.datastructures

local function trianglesphere(pos, r, edgecnt)
	-- Positions on the unit sphere
	local nodes = {
		{0, 1, 0},
		{1/math.sqrt(2), -1/math.sqrt(2), 0},
		{-1/math.sqrt(3), -1/math.sqrt(3), -1/math.sqrt(3)},
		{-1/math.sqrt(3), -1/math.sqrt(3), 1/math.sqrt(3)},
	}
	-- Indices to nodes: from, to and opposite points for triangles
	-- Invariance: e[1] < e[2] and e[3] < e[4]
	local edges = {{1,2, 3,4}, {1,3, 2,4}, {1,4, 2,3}, {2,3, 1,4}, {2,4, 1,3},
		{3,4, 1,2}}
	-- Use a heap to always retrieve the longest edge first
	local function edge_length_sqared(e)
		local p1 = nodes[e[1]]
		local p2 = nodes[e[2]]
		return (p2[1] - p1[1]) ^ 2 + (p2[2] - p1[2]) ^ 2 + (p2[3] - p1[3]) ^ 2
	end
	datastructures.create_binary_heap{
		input = edges,
		compare = function(e1, e2)
			-- Return true iff e1 is longer than e2
			return edge_length_sqared(e1) > edge_length_sqared(e2)
		end,
	}

	-- Repeatedly split longest edges in the middle
	-- May exceed edgecnt a bit
	while edges:size() < edgecnt do
		local e = edges:take()
		-- Add a new node at the split position
		local n_new = #nodes+1
		local n1 = e[1]
		local n2 = e[2]
		local node_new = {true}
		for c = 1,3 do
			node_new[c] = 0.5 * (nodes[n1][c] + nodes[n2][c])
		end
		local f = 1.0 / math.sqrt(node_new[1] ^ 2 + node_new[2] ^ 2 +
			node_new[3] ^ 2)
		for c = 1,3 do
			node_new[c] = f * node_new[c]
		end
		nodes[n_new] = node_new
		-- Update neighbouring edges (maybe this can be made faster)
		local neighbours = {{n1, e[3]}, {n1, e[4]}, {n2, e[3]}, {n2, e[4]}}
		local n_neigh = 4
		for i = 1,n_neigh do
			local neigh = neighbours[i]
			if neigh[1] > neigh[2] then
				neigh[1], neigh[2] = neigh[2], neigh[1]
			end
		end
		-- Do not loop backwards because neighbouring edges may be short
		--~ for i = edges:size(), 1, -1 do
		for i = 1, edges:size() do
			local e = edges[i]
			for i = 1,n_neigh do
				local neigh = neighbours[i]
				if e[1] == neigh[1] and e[2] == neigh[2] then
					-- Exactly one opposite needs to be set to n_new
					if e[3] == n1 or e[3] == n2 then
						e[3] = e[4]
						e[4] = n_new
					else
						e[4] = n_new
					end
					neighbours[i] = neighbours[n_neigh]
					n_neigh = n_neigh - 1
					if n_neigh == 0 then
						goto all_edges_updated  -- all are updated
					end
					break  -- test next edge
				end
			end
		end
::all_edges_updated::
		-- Add the new edges; n_new is always the biggest index
		edges:add{n1, n_new, e[3], e[4]}
		edges:add{n2, n_new, e[3], e[4]}
		edges:add{e[3], n_new, n1, n2}
		edges:add{e[4], n_new, n1, n2}
	end

	-- Create the triangles
	local n = #nodes
	local nn = n * n
	local existings = {}
	local function triangle_make_exist(n1, n2, n3)
		-- n1 < n2 holds, so move n3 with insertion sort
		if n2 > n3 then
			n2, n3 = n3, n2
			if n1 > n2 then
				n1, n2 = n2, n1
			end
		end
		--~ assert(n1 < n2 and n2 < n3)
		local i = n1 * nn + n2 * n + n3
		if existings[i] then
			return false
		end
		existings[i] = true
		return true
	end
	local tris = {}
	while not edges:is_empty() do
		local e = edges:take()
		if triangle_make_exist(e[1], e[2], e[3]) then
			tris[#tris+1] = {e[1], e[2], e[3]}
		end
		if triangle_make_exist(e[1], e[2], e[4]) then
			tris[#tris+1] = {e[1], e[2], e[4]}
		end
	end
	for i = 1,#tris do
		local tri = tris[i]
		for c = 1,3 do
			local node = nodes[tri[c]]
			tri[c] = {x = node[1], y = node[2], z = node[3]}
		end
	end
	-- Transform the triangles
	for i = 1,#tris do
		local tri = tris[i]
		for c = 1,3 do
			tri[c] = vector.add(vector.multiply(tri[c], r), pos)
		end
	end

	return tris
end

worldedit.register_command("myt", {
	description = "Test for triangle sphere",
	privs = {worldedit=true},
	params = "",
	require_pos = 1,
	func = function(playername)
		local pos1 = worldedit.pos1[playername]

		local triangles = trianglesphere(pos1, 40, 480)
		print(#triangles, dump(triangles))
		for i = 1,#triangles do
			local tri = triangles[i]
			local triangle_ps = vector.triangle(tri[1], tri[2], tri[3])
			for i = 1,#triangle_ps do
				local pos = triangle_ps[i]
				minetest.set_node(pos, {name="default:cobble"})
			end
		end

		return true
	end,
})


--[[
worldedit.register_command("myt", {
	description = "Test for vector extras triangle",
	privs = {worldedit=true},
	params = "",
	require_pos = 2,
	func = function(playername)
		--~ local pos1, pos2 = worldedit.sort_pos(worldedit.pos1[playername],
			--~ worldedit.pos2[playername])
		local pos1, pos2 = worldedit.pos1[playername],
			worldedit.pos2[playername]
		-- Can have float values
		local pos3 = minetest.get_player_by_name(playername):get_pos()

		local triangle_ps = vector.triangle(pos1, pos2, pos3)
		for i = 1,#triangle_ps do
			local pos = triangle_ps[i]
			minetest.set_node(pos, {name="default:wood"})
		end

		return true
	end,
})
--]]

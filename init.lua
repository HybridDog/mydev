
---------------------- Config --------------------------------------------------
-- rmin has to be >= zinz * 4 - 2
local rmin = 23
local rmax = 39
local zinz = 3
local roomheight = 5


----------------------- Helpers ------------------------------------------------

local blocklen = 4 * zinz - 2
local set = minetest.set_node
local get = minetest.get_node
local poshash = minetest.hash_node_position

local function hash2(x, y)
	return y * 0x10000 + x
end

vector.from_number = vector.from_number or function(z)
	return {x=z, y=z, z=z}
end


------------------------- Build funcs ------------------------------------------

-- returns a perlin chunk field of positions
local default_nparams = {
   offset = 0,
   scale = 1,
   seed = 3337,
   octaves = 6,
   persist = 0.6
}
local function get_perlin_field(rmin, rmax, nparams)
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
		local bare_dist = z*z
		for x=-r,r do
			local bare_dist = bare_dist+x*x
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

	for n,i in pairs(tab) do
		if i[3] then
			local new_pval = math.abs(i[3]/pval_diff - pval_min)
			if i[4] < new_pval then
				tab[n] = {i[1], i[2]}
			else
				tab[n] = nil
			end
		end
	end
	return tab
end

-- tests whether enough space is available for the block to fit in
local function block_fits(x,z, xzarea_h)
	for z = z, z + blocklen-1 do
		for x = x, x + blocklen-1 do
			if not xzarea_h[hash2(x, z)] then
				return false
			end
		end
	end
	return true
end

-- returns the block xz corners relative to pos
local boffs = {{0, -blocklen}, {-blocklen, 0}, {blocklen, 0}, {0, blocklen}}
local function get_block_xzs(xzarea_h)
	local blocks = {}
	local todo = {{math.random(blocklen) - 2, math.random(blocklen) - 2}}
	local avoid = {}
	local sp = 1
	while sp > 0 do
		local x,z = todo[sp][1],todo[sp][2]
		sp = sp-1
		for i = 1,#boffs do
			local x = x + boffs[i][1]
			local z = z + boffs[i][2]
			local h = hash2(x, z)
			if not avoid[h] then
				avoid[h] = true
				if block_fits(x,z, xzarea_h) then
					local p = {x, z}
					sp = sp+1
					todo[sp] = p
					blocks[#blocks+1] = p
				end
			end
		end
	end
	return blocks
end

-- finds the minimum y top of a block
local function block_minh(pos, x,z)
	local leasth = pos.y + 10 - 50
	for z = z, z + blocklen-1 do
		for x = x, x + blocklen-1 do
			local h
			local ystart = pos.y + 10
			-- search up
			for y = math.max(ystart, leasth+1), ystart + 13 do
				if get{x=pos.x+x, y=pos.y+y, z=pos.z+z}.name == "air" then
					break
				end
				h = y
			end
			if h then
				leasth = h
			else
				-- search down
				for y = ystart-1, leasth+1, -1 do
					if get{x=pos.x+x, y=pos.y+y, z=pos.z+z}.name ~= "air" then
						leasth = y
						break
					end
				end
			end
		end
	end
	return leasth
end

-- gives top heights to blocks
local function get_least_heights(block_xzs, pos)
	local height_offset = math.random(roomheight)-1
	local least_heights = {}
	for i = 1,#block_xzs do
		local x,z = unpack(block_xzs[i])
		local h = block_minh(pos, x,z)
		h = math.ceil((h + height_offset) / roomheight) * roomheight
		least_heights[hash2(x,z)] = h
	end
	return least_heights
end

-- tests whether a block can be added to x,y,z
local function is_block(y, block_xzs_h, tops, bottom, h)
	return y >= bottom
		and block_xzs_h[h]
		and y <= tops[h]
end

-- makes blocks 3d
local boffs3d = {
	{0, 0, -blocklen}, {-blocklen, 0, 0}, {blocklen, 0, 0}, {0, 0, blocklen},
	{0, -roomheight, 0}, {0, roomheight, 0},
}
local function get_blocks_3d(block_xzs, block_xzs_h, tops, bottom)
	local blocks = {}
	local x,z = unpack(block_xzs[1])
	local y = bottom

	local todo = {{x,y,z}}
	local avoid = {}
	local sp = 1
	while sp > 0 do
		local prev_block = todo[sp]
		local x,y,z = unpack(prev_block)
		sp = sp-1
		for i = 1,#boffs3d do
			local x = x + boffs3d[i][1]
			local y = y + boffs3d[i][2]
			local z = z + boffs3d[i][3]
			local h = poshash{x=x, y=y, z=z}
			if not avoid[h] then
				avoid[h] = true
				local xzh = hash2(x, z)
				if is_block(y, block_xzs_h, tops, bottom, xzh) then
					local p = {x, y, z, prev_block, y == tops[xzh]}
					sp = sp+1
					todo[sp] = p
					blocks[#blocks+1] = p
				end
			end
		end
	end
	return blocks
end

-- gets the building's blocks with their connections
local function get_blocks(xzarea_h, pos)
	local block_xzs = get_block_xzs(xzarea_h)
	local tops = get_least_heights(block_xzs, pos)

	local lowest_top
	for _,h in pairs(tops) do
		lowest_top = lowest_top and math.min(lowest_top, h) or h
	end
	local bottom = lowest_top - 2 * roomheight

	local block_xzs_h = {}
	for i = 1,#block_xzs do
		block_xzs_h[hash2(block_xzs[i][1], block_xzs[i][2])] = true
	end
	return get_blocks_3d(block_xzs, block_xzs_h, tops, bottom)
end

-- builds it
local function set_blocks(pos, blocks)
	local connections = {}
	for i = 1,#blocks do
		local x,y,z, toconnect, top = unpack(blocks[i])
		if toconnect then
			connections[#connections+1] = {blocks[i], toconnect}
		end
		-- set walls
		for y = y, y + roomheight-1 do
			for i = -1,1,2 do
				for x = x, x + blocklen-1 do
					local p = {x=pos.x+x, y=y, z=pos.z+z}
					if i == 1 then
						p.z = p.z + blocklen-1
					end
					set(p, {name="default:cobble"})
				end
				for z = z, z + blocklen-1 do
					local p = {x=pos.x+x, y=y, z=pos.z+z}
					if i == 1 then
						p.x = p.x + blocklen-1
					end
					set(p, {name="default:cobble"})
				end
			end
		end
		if top then
			-- battlements
			local o = 0
			for _ = 1,zinz do
				for i = 0,1 do
					local p = {x=pos.x+x+o+i, y=y+roomheight, z=pos.z+z}
					set(p, {name="default:cobble"})
					p.z = p.z + blocklen-1
					set(p, {name="default:cobble"})

					p = {x=pos.x+x, y=y+roomheight, z=pos.z+z+o+i}
					set(p, {name="default:cobble"})
					p.x = p.x + blocklen-1
					set(p, {name="default:cobble"})
				end
				o = o + 4
			end
		end
		-- set floor
		for z = z+1, z + blocklen-2 do
			for x = x+1, x + blocklen-2 do
				local p = {x=pos.x+x, y=y, z=pos.z+z}
				set(p, {name="default:stone"})
			end
		end
		-- set ceiling
		for z = z+1, z + blocklen-2 do
			for x = x+1, x + blocklen-2 do
				local p = {x=pos.x+x, y=y + roomheight-1, z=pos.z+z}
				set(p, {name = top and "default:dirt" or "default:meselamp"})
			end
		end
		-- set room air
		for z = z+1, z + blocklen-2 do
			for y = y+1, y + roomheight-2 do
				for x = x+1, x + blocklen-2 do
					local p = {x=pos.x+x, y=y, z=pos.z+z}
					set(p, {name="air"})
				end
			end
		end
	end
	for i = 1,#connections do
		local x1,y1,z1 = unpack(connections[i][1])
		local x2,y2,z2 = unpack(connections[i][2])
		if x1 ~= x2 then
			-- hole in the xwalls
			local x = math.max(x1, x2)
			for yo = 1,2 do
				local p = {x=pos.x+x, y=y1+yo, z=pos.z+z1+blocklen/2}
				set(p, {name="air"})
				p.x = p.x-1
				set(p, {name="air"})
			end
		elseif z1 ~= z2 then
			-- hole in zwalls
			local z = math.max(z1, z2)
			for yo = 1,2 do
				local p = {z=pos.z+z, y=y1+yo, x=pos.x+x1+blocklen/2}
				set(p, {name="air"})
				p.z = p.z-1
				set(p, {name="air"})
			end
		else
			-- ladder for climbing to the other room
			local y = y1 > y2 and y2 or y1
			for y = y+1, y+1 + roomheight do
				local p = {z=pos.z+z1+1, y=y, x=pos.x+x1+1}
				set(p, {name="default:ladder", param2=5})
			end
		end
	end
end

-- makes the building
local function burgr(pos)
	local xzarea = get_perlin_field(rmin, rmax)
	local xzarea_h = {}
	for i,v in pairs(xzarea) do
		xzarea_h[hash2(v[1], v[2])] = i
	end
	local blocks = get_blocks(xzarea_h, pos)
	set_blocks(pos, blocks)
end


-----------------------  -------------------------------------------------------

local d = {}
local d2
local function vmst(manip, pos)
	minetest.delay_function(1000, minetest.after, 0, function(manip, pos)
		vmst(manip, pos)
		d,d2 = d2,d
		manip:set_data(d)
		manip:write_to_map()
		burgr(pos)
		pos.z = pos.z + blocklen
	end, manip, pos)
end

local function cft(pos)
	burgr(pos)
	local manip = minetest.get_voxel_manip()
	local e1, e2 = manip:read_from_map(pos, pos)
	d2 = manip:get_data()
	vmst(manip, pos)
end


local TIME = 1

local clock = minetest.get_us_time
local us = TIME * 1000000
local function benchmark_function(fct, ...)
	local start = clock()
	local fin = start
	local total = 0
	while fin - start < us do
		fct(...)

		total = total + 1
		fin = clock()
	end
	return total * 1000000 / (fin - start)
end

--~ local function hasho(pos)
	--~ return (pos.z+32768)*65536*65536 + (pos.y+32768)*65536 + pos.x+32768
--~ end
--~ local function hashn(pos)
	--~ return bit.lshift(bit.lshift(pos.z + 0x8000, 16) + pos.y + 0x8000, 16)
			--~ + pos.x + 0x8000
--~ end
local function hasho(hash)
	local pos = {}
	pos.x = (hash%65536) - 32768
	hash = math.floor(hash/65536)
	pos.y = (hash%65536) - 32768
	hash = math.floor(hash/65536)
	pos.z = (hash%65536) - 32768
	return pos
end

local function hashn(hash)
	return {
		x = bit.band(hash, 0xffff) - 0x8000,
		y = bit.band(bit.rshift(hash, 16), 0xffff) - 0x8000,
		z = bit.band(bit.rshift(hash, 32), 0xffff) - 0x8000
	}
end

local cnt = 1000
local function enhtst()
	local maxv = 0xffffffffffff
	local ps = {}
	for i = 1,cnt do
		ps[i] = math.random(0, maxv)
		--~ ps[i] = {
			--~ x = math.random(-1000,1000),
			--~ y = math.random(-1000,1000),
			--~ z = math.random(-1000,1000)
		--~ }
	end
	print("old", benchmark_function(function()
		for i = 1,cnt do
			hasho(ps[i])
		end
	end))
	print("new", benchmark_function(function()
		for i = 1,cnt do
			hashn(ps[i])
		end
	end))

end

minetest.override_item("default:wood", {
	on_construct = enhtst
})

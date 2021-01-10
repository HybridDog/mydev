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

return funcs

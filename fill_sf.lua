local datastructures = mydev.datastructures
local common = mydev.common
local hash2 = common.hash2

-- Input: a 2D position {x, y} and a function can_go({x, y})
-- Output: a list of 2D positions (and the visited)
local function flood(startpos, can_go)
	local lifo = datastructures.create_stack()
	local fifo = datastructures.create_queue()
	local visited = {}
	local result = {}
	local cnt = 0
	lifo:push(startpos)
	local visit_cnt = 1
	visited[hash2(startpos[1], startpos[2])] = visit_cnt
	local use_stack = true
	repeat
		local p
		if (use_stack and not lifo:is_empty()) or fifo:is_empty() then
			p = lifo:pop()
		else
			p = fifo:take()
		end
		cnt = cnt + 1
		result[cnt] = p
		local next_ps = {{p[1]-1, p[2]}, {p[1], p[2]-1},
			{p[1]+1, p[2]}, {p[1], p[2]+1}}
		for k = 1,4 do
			local p_next = next_ps[k]
			local vi = hash2(p_next[1], p_next[2])
			if not visited[vi] and can_go(p_next) then
				visit_cnt = visit_cnt + 1
				visited[vi] = visit_cnt
				if use_stack then
					lifo:push(p_next)
				else
					fifo:add(p_next)
				end
				use_stack = not use_stack
			end
		end
	until lifo:is_empty() and fifo:is_empty()
	return result, visited, visit_cnt
end

return {flood = flood}

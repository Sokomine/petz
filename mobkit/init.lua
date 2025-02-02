-- yaw values:
-- x+ = -pi/2
-- x- = +pi/2
-- z+ = 0
-- z- = -pi

mobkit={}

mobkit.gravity = -9.8
mobkit.friction = 0.4	-- less is more

local abs = math.abs
local pi = math.pi
local floor = math.floor
local random = math.random
local sqrt = math.sqrt
local max = math.max
local min = math.min
local pow = math.pow

local sign = function(x)
	return (x<0) and -1 or 1
end

mobkit.terminal_velocity = sqrt(2*-mobkit.gravity*20) -- 20 meter fall = dead
mobkit.safe_velocity = sqrt(2*-mobkit.gravity*5) -- 5 m safe fall

local abr = minetest.get_mapgen_setting('active_block_range')

local neighbors ={
	{x=1,z=0},
	{x=1,z=1},
	{x=0,z=1},
	{x=-1,z=1},
	{x=-1,z=0},
	{x=-1,z=-1},
	{x=0,z=-1},
	{x=1,z=-1}
	}

	
-- UTILITY FUNCTIONS

function mobkit.dir2neighbor(dir)
	dir.y=0
	dir=vector.round(vector.normalize(dir))
	for k,v in ipairs(neighbors) do
		if v.x == dir.x and v.z == dir.z then return k end
	end
	return 1
end

function mobkit.neighbor_shift(neighbor,shift)	-- int shift: minus is left, plus is right
	return (8+neighbor+shift-1)%8+1
end

function mobkit.pos_shift(pos,vec) -- vec components can be omitted e.g. vec={y=1}
	vec.x=vec.x or 0
	vec.y=vec.y or 0
	vec.z=vec.z or 0
	return {x=pos.x+vec.x,
			y=pos.y+vec.y,
			z=pos.z+vec.z}
end

function mobkit.pos_translate2d(pos,yaw,dist) -- translate pos dist distance in yaw direction
	return vector.add(pos,vector.multiply(minetest.yaw_to_dir(yaw),dist))
end

function mobkit.is_pos_in_box(pos,bpos,box)
	return pos.x > bpos.x+box[1] and pos.x < bpos.x+box[4] and
			pos.y > bpos.y+box[2] and pos.y < bpos.y+box[5] and
			pos.z > bpos.z+box[3] and pos.z < bpos.z+box[6]
end

-- call this instead if you want feet position.
--[[
function mobkit.get_stand_pos(thing)	-- thing can be luaentity or objectref.
	if type(thing) == 'table' then
		return mobkit.pos_shift(thing.object:get_pos(),{y=thing.collisionbox[2]+0.01})
	elseif type(thing) == 'userdata' then
		local colbox = thing:get_properties().collisionbox
		return mobkit.pos_shift(thing:get_pos(),{y=colbox[2]+0.01})
	end
end	--]]

function mobkit.get_stand_pos(thing)	-- thing can be luaentity or objectref.
	local pos = {}
	local colbox = {}
	if type(thing) == 'table' then
		pos = thing.object:get_pos()
		colbox = thing.collisionbox
	elseif type(thing) == 'userdata' then
		pos = thing:get_pos()
		colbox = thing:get_properties().collisionbox
	else 
		return false
	end
	return mobkit.pos_shift(pos,{y=colbox[2]+0.01}), pos
end

function mobkit.nodeatpos(pos)
	local node = minetest.get_node_or_nil(pos)
	if node then return minetest.registered_nodes[node.name] end
end

function mobkit.get_nodename_off(pos,vec)
	return minetest.get_node(mobkit.pos_shift(pos,vec)).name
end

function mobkit.get_node_pos(pos)
	return  {
			x=floor(pos.x+0.5),
			y=floor(pos.y+0.5),
			z=floor(pos.z+0.5),
			}
end

function mobkit.get_nodes_in_area(pos1,pos2,full)
	local npos1=mobkit.get_node_pos(pos1)
	local npos2=mobkit.get_node_pos(pos2)
	local result = {}
	local cnt = 0	-- safety
	
	local sx = (pos2.x<pos1.x) and -1 or 1
	local sz = (pos2.z<pos1.z) and -1 or 1
	local sy = (pos2.y<pos1.y) and -1 or 1
	
	local x=npos1.x-sx
	local z=npos1.z-sz
	local y=npos1.y-sy
	
	repeat
		x=x+sx
		z=npos1.z-sz
		repeat
			z=z+sz
			y=npos1.y-sy
			repeat
				y=y+sy
				
				local pos = {x=x,y=y,z=z}
				if full==true then
					result[pos] = minetest.registered_nodes[minetest.get_node(pos).name]
				else
					result[minetest.registered_nodes[minetest.get_node(pos).name]] = true
				end
			
				cnt=cnt+1
				if cnt > 125 then 
					minetest.chat_send_all('get_nodes_in_area: area too big ')
					return result
				end
			
			until y==npos2.y
		until z==npos2.z
	until x==npos2.x
	
	return result
end

function mobkit.get_hitbox_bottom(self)
	local y = self.collisionbox[2]
	local pos = self.object:get_pos()
	return {
			{x=pos.x+self.collisionbox[1],y=pos.y+y,z=pos.z+self.collisionbox[3]},
			{x=pos.x+self.collisionbox[1],y=pos.y+y,z=pos.z+self.collisionbox[6]},
			{x=pos.x+self.collisionbox[4],y=pos.y+y,z=pos.z+self.collisionbox[3]},
			{x=pos.x+self.collisionbox[4],y=pos.y+y,z=pos.z+self.collisionbox[6]},
		}
end
		
function mobkit.get_node_height(pos)
	local npos = mobkit.get_node_pos(pos)
	local node = mobkit.nodeatpos(npos)
	if node == nil then return nil end
	
	if node.walkable then
		if node.drawtype == 'nodebox' then
			if node.node_box == nil then return nil end  --added by petz
			if node.node_box.type == 'fixed' then
				if type(node.node_box.fixed[1]) == 'number' then
					return npos.y + node.node_box.fixed[5] ,0, false
				elseif type(node.node_box.fixed[1]) == 'table' then
					return npos.y + node.node_box.fixed[1][5] ,0, false
				else
					return npos.y + 0.5,1, false			-- todo handle table of boxes
				end		
			elseif node.node_box.type == 'leveled' then
				return minetest.get_node_level(pos)/64-0.5+mobkit.get_node_pos(pos).y, 0, false
			else
				return npos.y + 0.5,1, false	-- the unforeseen
			end
		else
			return npos.y+0.5,1, false	-- full node
		end
	else
		local liquidflag = false
		if node.drawtype == 'liquid' then liquidflag = true end
		return npos.y-0.5,-1,liquidflag	
	end
end

-- get_terrain_height
-- steps(optional) number of recursion steps; default=3
-- dir(optional) is 1=up, -1=down, 0=both; default=0
-- liquidflag(forbidden) never provide this parameter.
function mobkit.get_terrain_height(pos,steps,dir,liquidflag) --dir is 1=up, -1=down, 0=both 
	steps = steps or 3
	dir = dir or 0

	local h,f,l = mobkit.get_node_height(pos)
	if h == nil then return nil end
	if l then liquidflag = true end
	
	if f==0 then 
		return h, liquidflag
	end
	
	if dir==0 or dir==f then
		steps = steps - 1
		if steps <=0 then return nil end
		return mobkit.get_terrain_height(mobkit.pos_shift(pos,{y=f}),steps,f,liquidflag)
	else
		return h, liquidflag
	end
end

function mobkit.get_spawn_pos_abr(dtime,intrvl,radius,chance,reduction)
	local plyrs = minetest.get_connected_players()
	intrvl=1/intrvl

	if random()<dtime*(intrvl*#plyrs) then
		local plyr = plyrs[random(#plyrs)]		-- choose random player
		local vel = plyr:get_player_velocity()
		local spd = vector.length(vel)
		chance = (1-chance) * 1/(spd*0.75+1)
		
		local yaw
		if spd > 1 then
			-- spawn in the front arc
			yaw = minetest.dir_to_yaw(vel) + random()*0.35 - 0.75
		else
			-- random yaw
			yaw = random()*pi*2 - pi
		end
		local pos = plyr:get_pos()
		local dir = vector.multiply(minetest.yaw_to_dir(yaw),radius)
		local pos2 = vector.add(pos,dir)
		pos2.y=pos2.y-5
		local height, liquidflag = mobkit.get_terrain_height(pos2,32)
		if height then
			local objs = minetest.get_objects_inside_radius(pos,radius*1.1)
			for _,obj in ipairs(objs) do				-- count mobs in abrange
				if not obj:is_player() then
					local lua = obj:get_luaentity()
					if lua and lua.name ~= '__builtin:item' then
						chance=chance + (1-chance)*reduction	-- chance reduced for every mob in range
					end
				end
			end
			if chance < random() then
				pos2.y = height
				objs = minetest.get_objects_inside_radius(pos2,radius*0.95)
				for _,obj in ipairs(objs) do				-- do not spawn if another player around
					if obj:is_player() then return end
				end
				return pos2, liquidflag
			end
		end
	end
end

function mobkit.turn2yaw(self,tyaw,rate)
	tyaw = tyaw or 0 --temp
	rate = rate or 6
		local yaw = self.object:get_yaw()
		yaw = yaw+pi
		tyaw=(tyaw+pi)%(pi*2)
		
		local step=min(self.dtime*rate,abs(tyaw-yaw)%(pi*2))
		
		local dir = abs(tyaw-yaw)>pi and -1 or 1
		dir = tyaw>yaw and dir*1 or dir * -1
		
		local nyaw = (yaw+step*dir)%(pi*2)
		self.object:set_yaw(nyaw-pi)
		
		if nyaw==tyaw then return true
		else return false end
end

function mobkit.dir_to_rot(v,rot)
	rot = rot or {x=0,y=0,z=0}
	return {x = (v.x==0 and v.y==0 and v.z==0) and rot.x or math.atan2(v.y,vector.length({x=v.x,y=0,z=v.z})),
			y = (v.x==0 and v.z==0) and rot.y or minetest.dir_to_yaw(v),
			z=rot.z}
end

function mobkit.isnear2d(p1,p2,thresh)
	if abs(p2.x-p1.x) < thresh and abs(p2.z-p1.z) < thresh then
		return true
	else
		return false
	end
end

-- object has reached the destination if dest is in the rear half plane.
function mobkit.is_there_yet2d(pos,dir,dest) -- obj positon; facing vector; destination position

	local c = -dir.x*pos.x-dir.z*pos.z						-- the constant		
	
	if dir.z > 0 then		
		return dest.z <= (-dir.x*dest.x - c)/dir.z			-- line equation
	elseif dir.z < 0 then
		return dest.z >= (-dir.x*dest.x - c)/dir.z
	elseif dir.x > 0 then
		return dest.x <= (-dir.z*dest.z - c)/dir.x
	elseif dir.x < 0 then
		return dest.x >= (-dir.z*dest.z - c)/dir.x
	else
		return false
	end
	
end

function mobkit.isnear3d(p1,p2,thresh)
	if abs(p2.x-p1.x) < thresh and abs(p2.z-p1.z) < thresh and abs(p2.y-p1.y) < thresh then
		return true
	else
		return false
	end
end

function mobkit.is_alive(thing)		-- thing can be luaentity or objectref.
--	if not thing then return false end
	if not mobkit.exists(thing) then return false end
	if type(thing) == 'table' then return thing.hp > 0 end
	if thing:is_player() then return thing:get_hp() > 0
	else 
		local lua = thing:get_luaentity()
		local hp = lua and lua.hp or nil
		return hp and hp > 0
	end
end

function mobkit.exists(thing)
	if not thing then return false end
	if type(thing) == 'table' then thing=thing.object end
	if type(thing) == 'userdata' then 
		if thing:is_player() then
			if thing:get_look_horizontal() then return true end 
		else
			if thing:get_yaw() then return true end
		end
	end
end

function mobkit.hurt(luaent,dmg)
	if not luaent then return false end
	if type(luaent) == 'table' then
		luaent.hp = max((luaent.hp or 0) - dmg,0)
	end
end

function mobkit.heal(luaent,dmg)
	if not luaent then return false end
	if type(luaent) == 'table' then
		luaent.hp = min(luaent.max_hp,(luaent.hp or 0) + dmg)
	end
end

-- function mobkit.animate(self,anim)
	-- if self.animation and self.animation[anim] then
		-- local crange = self.object:get_animation().range
		-- if not crange
		-- or crange.x ~= self.animation[anim].range.x
		-- or crange.y ~= self.animation[anim].range.y then 	
			-- self.object:set_animation(self.animation[anim].range,self.animation[anim].speed,0,self.animation[anim].loop)
		-- end
	-- end
-- end

function mobkit.animate(self,anim)
	if self.animation and self.animation[anim] then
		if self._anim == anim then return end
		self._anim=anim
		
		local aparms = {}
		if #self.animation[anim] > 0 then
			aparms = self.animation[anim][random(#self.animation[anim])]
		else
			aparms = self.animation[anim]
		end
		
		self.object:set_animation(aparms.range,aparms.speed,0,aparms.loop)
	else
		self._anim = nil
	end
end

function mobkit.make_sound(self,sound)
	if self.sounds and self.sounds[sound] then
		minetest.sound_play(self.sounds[sound], {object=self.object})
	end
end

function mobkit.is_neighbor_node_reachable(self,neighbor)	-- todo: take either number or pos
	local offset = neighbors[neighbor]
	local pos=mobkit.get_stand_pos(self)
	local tpos = mobkit.get_node_pos(mobkit.pos_shift(pos,offset))
	local node_name = minetest.get_node(tpos).name --added by petz
	if node_name:find("fence") then return  --added by petz
		elseif node_name:find("gate") and node_name:find("closed") then return end  --added by petz	
	local height, liquidflag = mobkit.get_terrain_height(tpos)

	if height and abs(height-pos.y) <= self.jump_height then
		tpos.y = height
		height = height - pos.y
		
		-- don't cut corners
		if neighbor % 2 == 0 then				-- diagonal neighbors are even
			local n2 = neighbor-1				-- left neighbor never < 0
			offset = neighbors[n2]
			local t2 = mobkit.get_node_pos(mobkit.pos_shift(pos,offset))
			local h2 = mobkit.get_terrain_height(t2)
			if h2 and h2 - pos.y > 0.02 then return end
			n2 = (neighbor+1)%8 		-- right neighbor
			offset = neighbors[n2]
			t2 = mobkit.get_node_pos(mobkit.pos_shift(pos,offset))
			h2 = mobkit.get_terrain_height(t2)
			if h2 and h2 - pos.y > 0.02 then return end
		end
	
		-- check headroom
		if tpos.y+self.height-pos.y > 1 then			-- if head in next node above, else no point checking headroom
			local snpos = mobkit.get_node_pos(pos)
			local pos1 = {x=pos.x,y=snpos.y+1,z=pos.z}						-- current pos plus node up
			local pos2 = {x=tpos.x,y=tpos.y+self.height,z=tpos.z}			-- target head pos

			local nodes = mobkit.get_nodes_in_area(pos1,pos2,true)
			
			for p,node in pairs(nodes) do
				if snpos.x==p.x and snpos.z==p.z then 
					if node.name=='ignore' or node.walkable then return end
				else
					if node.name=='ignore' or 
					(node.walkable and mobkit.get_node_height(p)>tpos.y+0.001) then return end
				end
			end
		end
		
		return height, tpos, liquidflag
	else
		return
	end
end

function mobkit.get_next_waypoint(self,tpos)
	local pos = mobkit.get_stand_pos(self)
	local dir=vector.direction(pos,tpos)
	local neighbor = mobkit.dir2neighbor(dir)
	local function update_pos_history(self,pos)
		table.insert(self.pos_history,1,pos)
		if #self.pos_history > 2 then table.remove(self.pos_history,#self.pos_history) end
	end
	local nogopos = self.pos_history[2]
	
	local height, pos2, liquidflag = mobkit.is_neighbor_node_reachable(self,neighbor)
--minetest.chat_send_all('pos2 ' .. minetest.serialize(pos2))
--minetest.chat_send_all('nogopos ' .. minetest.serialize(nogopos))	
	if height and not liquidflag 
	and not (nogopos and mobkit.isnear2d(pos2,nogopos,0.1)) then

		local heightl = mobkit.is_neighbor_node_reachable(self,mobkit.neighbor_shift(neighbor,-1))
		if heightl and abs(heightl-height)<0.001 then
			local heightr = mobkit.is_neighbor_node_reachable(self,mobkit.neighbor_shift(neighbor,1))
			if heightr and abs(heightr-height)<0.001 then
				dir.y = 0
				local dirn = vector.normalize(dir)
				local npos = mobkit.get_node_pos(mobkit.pos_shift(pos,neighbors[neighbor]))
				local factor = abs(dirn.x) > abs(dirn.z) and abs(npos.x-pos.x) or abs(npos.z-pos.z)
				pos2=mobkit.pos_shift(pos,{x=dirn.x*factor,z=dirn.z*factor})
			end
		end
		update_pos_history(self,pos2)
		return height, pos2
	else

		for i=1,3 do
			-- scan left
			local height, pos2, liq = mobkit.is_neighbor_node_reachable(self,mobkit.neighbor_shift(neighbor,-i*self.path_dir))
			if height and not liq 
			and not (nogopos and mobkit.isnear2d(pos2,nogopos,0.1)) then
				update_pos_history(self,pos2)
				return height,pos2 
			end			
			-- scan right
			height, pos2, liq = mobkit.is_neighbor_node_reachable(self,mobkit.neighbor_shift(neighbor,i*self.path_dir))
			if height and not liq 
			and not (nogopos and mobkit.isnear2d(pos2,nogopos,0.1)) then
				update_pos_history(self,pos2)
				return height,pos2 
			end
		end
		--scan rear
		height, pos2, liq = mobkit.is_neighbor_node_reachable(self,mobkit.neighbor_shift(neighbor,4))
		if height and not liq 
		and not (nogopos and mobkit.isnear2d(pos2,nogopos,0.1)) then
			update_pos_history(self,pos2)
			return height,pos2 
		end
	end
	-- stuck condition here
	table.remove(self.pos_history,2)
	self.path_dir = self.path_dir*-1	-- subtle change in pathfinding
end

function mobkit.get_next_waypoint_fast(self,tpos,nogopos)
	local pos = mobkit.get_stand_pos(self)
	local dir=vector.direction(pos,tpos)
	local neighbor = mobkit.dir2neighbor(dir)
	local height, pos2, liquidflag = mobkit.is_neighbor_node_reachable(self,neighbor)
	
	if height and not liquidflag then
		local fast = false
		heightl = mobkit.is_neighbor_node_reachable(self,mobkit.neighbor_shift(neighbor,-1))
		if heightl and abs(heightl-height)<0.001 then
			heightr = mobkit.is_neighbor_node_reachable(self,mobkit.neighbor_shift(neighbor,1))
			if heightr and abs(heightr-height)<0.001 then
				fast = true
				dir.y = 0
				local dirn = vector.normalize(dir)
				local npos = mobkit.get_node_pos(mobkit.pos_shift(pos,neighbors[neighbor]))
				local factor = abs(dirn.x) > abs(dirn.z) and abs(npos.x-pos.x) or abs(npos.z-pos.z)
				pos2=mobkit.pos_shift(pos,{x=dirn.x*factor,z=dirn.z*factor})
			end
		end
		return height, pos2, fast
	else

		for i=1,4 do
			-- scan left
			height, pos2, liq = mobkit.is_neighbor_node_reachable(self,mobkit.neighbor_shift(neighbor,-i))
			if height and not liq then return height,pos2 end
			-- scan right
			height, pos2, liq = mobkit.is_neighbor_node_reachable(self,mobkit.neighbor_shift(neighbor,i))
			if height and not liq then return height,pos2 end
		end
	end
end

function mobkit.goto_next_waypoint(self,tpos)
	local height, pos2 = mobkit.get_next_waypoint(self,tpos)
	
	if not height then return false end
	
	if height <= 0.01 then
		local yaw = self.object:get_yaw()
		local tyaw = minetest.dir_to_yaw(vector.direction(self.object:get_pos(),pos2))
		if abs(tyaw-yaw) > 1 then
			mobkit.lq_turn2pos(self,pos2) 
		end
		mobkit.lq_dumbwalk(self,pos2)
	else
		mobkit.lq_turn2pos(self,pos2) 
		mobkit.lq_dumbjump(self,height) 
	end
	return true
end

function mobkit.go_forward_horizontal(self,yaw,speed)	-- sets velocity in yaw direction, y component unaffected
	local y = self.object:get_velocity().y
	local vel = vector.multiply(minetest.yaw_to_dir(yaw),speed)
	vel.y = y
	self.object:set_velocity(vel)
end

function mobkit.timer(self,s) -- returns true approx every s seconds
	local t1 = floor(self.time_total)
	local t2 = floor(self.time_total+self.dtime)
	if t2>t1 and t2%s==0 then return true end
end

-- Memory functions. 
-- Stuff in memory is serialized, never try to remember objectrefs.
function mobkit.remember(self,key,val)
	self.memory[key]=val
	return val
end

function mobkit.forget(self,key)
	self.memory[key] = nil
end

function mobkit.recall(self,key)
	return self.memory[key]
end

-- Queue functions
function mobkit.queue_high(self,func,priority)
	local maxprty = mobkit.get_queue_priority(self)
	if priority > maxprty then
		mobkit.clear_queue_low(self)
	end

	for i,f in ipairs(self.hqueue) do
		if priority > f.prty then
			table.insert(self.hqueue,i,{func=func,prty=priority})
			return
		end
	end
	table.insert(self.hqueue,{func=func,prty=priority})
end

function mobkit.queue_low(self,func)
	table.insert(self.lqueue,func)
end

function mobkit.is_queue_empty_low(self)
	if #self.lqueue == 0 then return true
	else return false end
end

function mobkit.clear_queue_high(self)
	self.hqueue = {}
end

function mobkit.clear_queue_low(self)
	self.lqueue = {}
end

function mobkit.get_queue_priority(self)
	if #self.hqueue > 0 then
		return self.hqueue[1].prty
	else return 0 end
end

function mobkit.is_queue_empty_high(self)
	if #self.hqueue == 0 then return true
	else return false end
end

function mobkit.get_nearby_player(self)	-- returns random player if nearby or nil
	for _,obj in ipairs(self.nearby_objects) do
		if obj:is_player() and mobkit.is_alive(obj) then return obj end
	end
	return
end

function mobkit.get_nearby_entity(self,name)	-- returns random nearby entity of name or nil
	for _,obj in ipairs(self.nearby_objects) do
		if mobkit.is_alive(obj) and not obj:is_player() and obj:get_luaentity().name == name then return obj end
	end
	return
end

function mobkit.get_closest_entity(self,name)	-- returns closest entity of name or nil
	local cobj = nil
	local dist = abr*64
	local pos = self.object:get_pos()
	for _,obj in ipairs(self.nearby_objects) do
		local luaent = obj:get_luaentity()
		if mobkit.is_alive(obj) and not obj:is_player() and luaent and luaent.name == name then
			local opos = obj:get_pos()
			local odist = abs(opos.x-pos.x) + abs(opos.z-pos.z)
			if odist < dist then
				dist=odist
				cobj=obj
			end
		end
	end
	return cobj
end

local function execute_queues(self)
	--Execute hqueue
	if #self.hqueue > 0 then
		local func = self.hqueue[1].func
		if func(self) then
			table.remove(self.hqueue,1)
			self.lqueue = {}
		end
	end
	-- Execute lqueue
	if #self.lqueue > 0 then
		local func = self.lqueue[1]
		if func(self) then
			table.remove(self.lqueue,1)
		end
	end
end

local function sensors()
	local timer = 2
	local pulse = 1
	return function(self)
		timer=timer-self.dtime
		if timer < 0 then
		
			pulse = pulse + 1				-- do full range every third scan
			local range = self.view_range
			if pulse > 2 then 
				pulse = 1
			else
				range = self.view_range*0.5
			end
			
			local pos = self.object:get_pos()
--local tim = minetest.get_us_time()
			self.nearby_objects = minetest.get_objects_inside_radius(pos, range)
--minetest.chat_send_all(minetest.get_us_time()-tim)
			for i,obj in ipairs(self.nearby_objects) do	
				if obj == self.object then
					table.remove(self.nearby_objects,i)
					break
				end
			end
			timer=2
		end
	end
end

------------
-- CALLBACKS
------------

function mobkit.default_brain(self)
	if mobkit.is_queue_empty_high(self) then mobkit.hq_roam(self,0) end
end

function mobkit.statfunc(self)
	local tmptab={}
	tmptab.memory = self.memory
	tmptab.hp = self.hp
	tmptab.texture_no = self.texture_no
	return minetest.serialize(tmptab)
end

function mobkit.actfunc(self, staticdata, dtime_s)
	self.lqueue = {}
	self.hqueue = {}
	self.nearby_objects = {}
	self.nearby_players = {}
	self.pos_history = {}
	self.path_dir = 1
	self.time_total = 0

	local sdata = minetest.deserialize(staticdata)
	if sdata then 
		for k,v in pairs(sdata) do
			self[k] = v
		end
	end
	
	if self.timeout and self.timeout>0 and dtime_s > self.timeout and next(self.memory)==nil then
		self.object:remove()
	end
	
	if not self.memory then 		-- this is the initial activation
		self.memory = {} 
		
		-- texture variation
		if #self.textures > 1 then self.texture_no = random(#self.textures) end
	end
	
	-- apply texture
	if self.texture_no then
		local props = {}
		props.textures = {self.textures[self.texture_no]}
		self.object:set_properties(props)
	end

--hp
	self.hp = self.hp or (self.max_hp or 10)
--armor
	if type(self.armor_groups) ~= 'table' then
		self.armor_groups={}
	end
	self.armor_groups.immortal = 1
	self.object:set_armor_groups(self.armor_groups)
	
	self.oxygen = self.oxygen or self.lung_capacity
	self.lastvelocity = {x=0,y=0,z=0}
	self.height = self.collisionbox[5] - self.collisionbox[2]
	self.sensefunc=sensors()
end

function mobkit.stepfunc(self,dtime)	-- not intended to be modified
	self.dtime = dtime
--  physics comes first
--	self.object:set_acceleration({x=0,y=mobkit.gravity,z=0})
	local vel = self.object:get_velocity()
	
--	if self.lastvelocity.y == vel.y then
	if abs(self.lastvelocity.y-vel.y)<0.001 then
		self.isonground = true
	else
		self.isonground = false
	end
	
	-- dumb friction
	if self.isonground and not(self.can_fly) then  --added by petz
		self.object:set_velocity({x= vel.x> 0.2 and vel.x*mobkit.friction or 0,
								y=vel.y,
								z=vel.z > 0.2 and vel.z*mobkit.friction or 0})
	end
	
-- bounciness
	if self.springiness and self.springiness > 0 then
		local vnew = vector.new(vel)
		
		if not self.collided then						-- ugly workaround for inconsistent collisions
			for _,k in ipairs({'y','z','x'}) do			
				if vel[k]==0 and abs(self.lastvelocity[k])> 0.1 then 
					vnew[k]=-self.lastvelocity[k]*self.springiness 
				end
			end
		end
		
		if not vector.equals(vel,vnew) then
			self.collided = true
		else
			if self.collided then
				vnew = vector.new(self.lastvelocity)
			end
			self.collided = false
		end
		
		self.object:set_velocity(vnew)
	end
	
	-- buoyancy
	local spos = mobkit.get_stand_pos(self)
	spos.y = spos.y+0.01
	-- get surface height
--	local surface = mobkit.get_node_pos(spos).y+0.5
	local surface = nil
	local snodepos = mobkit.get_node_pos(spos)
	local surfnode = mobkit.nodeatpos(spos)
	if mobkit.is_alive(self) and not(self.is_baby) then --added by petz
		local stand_pos = spos --added by petz
		stand_pos.y = spos.y + 0.5 --added by petz
		local stand_node_pos = mobkit.get_node_pos(stand_pos) --added by petz
		local stand_node = mobkit.nodeatpos(stand_node_pos) --added by petz
		if stand_node and stand_node.walkable and stand_node.drawtype == "normal" then 	-- if standing inside solid block then jump to escape --added by petz
			self.object:set_pos({ --added by petz
				x = stand_pos.x, --added by petz
				y = stand_pos.y + self.jump_height, --added by petz
				z = stand_pos.z --added by petz
			}) --added by petz
		end --added by petz
	end --added by petz
	while surfnode and surfnode.drawtype == 'liquid' do
		surface = snodepos.y+0.5
		if surface > spos.y+self.height then break end
		snodepos.y = snodepos.y+1
		surfnode = mobkit.nodeatpos(snodepos)
	end
	if surface then				-- standing in liquid
		self.isinliquid = true
		local submergence = min(surface-spos.y,self.height)
		local balance = self.buoyancy*self.height
		local buoyacc = mobkit.gravity*((balance - submergence)^2/balance^2*sign(balance - submergence))
		self.object:set_acceleration({x=-vel.x,y=buoyacc-vel.y*abs(vel.y)*0.7,z=-vel.z})
	else
		self.isinliquid = false
		if not(self.can_fly) then  --added by petz
			self.object:set_acceleration({x=0,y=mobkit.gravity,z=0})
		end  --added by petz
	end
	
	
	
	-- local footnode = mobkit.nodeatpos(spos)
	-- local headnode
	-- if footnode and footnode.drawtype == 'liquid' then
		
		-- vel = self.object:get_velocity()
		-- headnode = mobkit.nodeatpos(mobkit.pos_shift(spos,{y=self.height or 0}))	-- TODO: height may be nil
		-- local submergence = headnode.drawtype=='liquid' 
			-- and	self.buoyancy-1
			-- or (self.buoyancy*self.height-(1-(spos.y+0.5)%1))^2/(self.buoyancy*self.height)^2*sign(self.buoyancy*self.height-(1-(spos.y+0.5)%1))

		-- local buoyacc = submergence * mobkit.gravity
		-- self.object:set_acceleration({x=-vel.x,y=buoyacc-vel.y*abs(vel.y)*0.5,z=-vel.z})

	-- end

	if self.brainfunc then
		-- vitals: fall damage
		vel = self.object:get_velocity()
		local velocity_delta = abs(self.lastvelocity.y - vel.y)
		if velocity_delta > mobkit.safe_velocity then
			self.hp = self.hp - floor((self.max_hp-100) * min(1, velocity_delta/mobkit.terminal_velocity))
		end
		
		-- vitals: oxygen
		if self.lung_capacity then
			local headnode = mobkit.nodeatpos(mobkit.pos_shift(self.object:get_pos(),{y=self.collisionbox[5]})) -- node at hitbox top
			if headnode and headnode.drawtype == 'liquid' then 
				self.oxygen = self.oxygen - self.dtime
			else
				self.oxygen = self.lung_capacity
			end
				
			if self.oxygen <= 0 then self.hp=0 end	-- drown
		end

		
		self:sensefunc()
		self:brainfunc()
		execute_queues(self)
	end
	
	self.lastvelocity = self.object:get_velocity()
	self.time_total=self.time_total+self.dtime
end

----------------------------
-- BEHAVIORS
----------------------------
-- LOW LEVEL QUEUE FUNCTIONS
----------------------------

function mobkit.lq_turn2pos(self,tpos)
	local func=function(self)
		local pos = self.object:get_pos()
		return mobkit.turn2yaw(self,
			minetest.dir_to_yaw(vector.direction(pos,tpos)))
	end
	mobkit.queue_low(self,func)
end

function mobkit.lq_idle(self,duration,anim)
	anim = anim or 'stand'
	local init = true
	local func=function(self)
		if init then 
			mobkit.animate(self,anim) 
			init=false
		end
		duration = duration-self.dtime
		if duration <= 0 then return true end
	end
	mobkit.queue_low(self,func)
end

function mobkit.lq_dumbwalk(self,dest,speed_factor)
	local timer = 3			-- failsafe
	speed_factor = speed_factor or 1
	local func=function(self)
		mobkit.animate(self,'walk')
		timer = timer - self.dtime
		if timer < 0 then return true end
		
		local pos = mobkit.get_stand_pos(self)
		local y = self.object:get_velocity().y

		if mobkit.is_there_yet2d(pos,minetest.yaw_to_dir(self.object:get_yaw()),dest) then
--		if mobkit.isnear2d(pos,dest,0.25) then
			if not self.isonground or abs(dest.y-pos.y) > 0.1 then		-- prevent uncontrolled fall when velocity too high
--			if abs(dest.y-pos.y) > 0.1 then	-- isonground too slow for speeds > 4
				self.object:set_velocity({x=0,y=y,z=0})
			end
			return true 
		end

		if self.isonground then
			local dir = vector.normalize(vector.direction({x=pos.x,y=0,z=pos.z},
														{x=dest.x,y=0,z=dest.z}))
			dir = vector.multiply(dir,self.max_speed*speed_factor)
--			self.object:set_yaw(minetest.dir_to_yaw(dir))
			mobkit.turn2yaw(self,minetest.dir_to_yaw(dir))
			dir.y = y
			self.object:set_velocity(dir)
		end
	end
	mobkit.queue_low(self,func)
end

-- initial velocity for jump height h, v= a*sqrt(h*2/a) ,add 20%
function mobkit.lq_dumbjump(self,height,anim)
	anim = anim or 'stand'
	local jump = true
	local func=function(self)
	local yaw = self.object:get_yaw()
		if self.isonground then
			if jump then
				mobkit.animate(self,anim)
				local dir = minetest.yaw_to_dir(yaw)
				dir.y = -mobkit.gravity*sqrt((height+0.35)*2/-mobkit.gravity)
				self.object:set_velocity(dir)
				jump = false
			else				-- the eagle has landed
				return true
			end
		else	
			local dir = minetest.yaw_to_dir(yaw)
			local vel = self.object:get_velocity()
			if self.lastvelocity.y < 0.9 then
				dir = vector.multiply(dir,3)
			end
			dir.y = vel.y
			self.object:set_velocity(dir,yaw)
		end
	end
	mobkit.queue_low(self,func)
end

function mobkit.lq_jumpout(self)
	local phase = 1
	local func=function(self)
		local vel=self.object:get_velocity()
		if phase == 1 then
			vel.y=vel.y+5
			self.object:set_velocity(vel)
			phase = 2
		else
			if vel.y < 0 then return true end
			local dir = minetest.yaw_to_dir(self.object:get_yaw())
			dir.y=vel.y
			self.object:set_velocity(dir)
		end
	end
	mobkit.queue_low(self,func)
end

function mobkit.lq_freejump(self)
	local phase = 1
	local func=function(self)
		local vel=self.object:get_velocity()
		if phase == 1 then
			vel.y=vel.y+6
			self.object:set_velocity(vel)
			phase = 2
		else
			if vel.y <= 0.01 then return true end
			local dir = minetest.yaw_to_dir(self.object:get_yaw())
			dir.y=vel.y
			self.object:set_velocity(dir)
		end
	end
	mobkit.queue_low(self,func)
end

function mobkit.lq_jumpattack(self,height,target)
	local phase=1		
	local func=function(self)
		if not mobkit.is_alive(target) then return true end
		if self.isonground then
			if phase==1 then	-- collision bug workaround
				local vel = self.object:get_velocity()
				vel.y = -mobkit.gravity*sqrt(height*2/-mobkit.gravity)
				self.object:set_velocity(vel)
				mobkit.make_sound(self,'charge')
				phase=2
			else
				return true
			end
		elseif phase==2 then
			local dir = minetest.yaw_to_dir(self.object:get_yaw())
			local vy = self.object:get_velocity().y
			dir=vector.multiply(dir,6)
			dir.y=vy
			self.object:set_velocity(dir)
			phase=3
		elseif phase==3 then	-- in air
			local twidth = target:get_properties().collisionbox[1]
			local pos = self.object:get_pos()
			-- calculate attack spot
			local dir = minetest.yaw_to_dir(self.object:get_yaw())
			dir2 = vector.add(dir,self.attack.range+twidth)
			local apos = vector.add(pos,dir2)
--			local tpos = mobkit.get_stand_pos(target) 						--test
--			tpos.y = tpos.y+height
			if mobkit.isnear2d(apos,target:get_pos(),0.25) then	--bite
				target:punch(self.object,1,self.attack)
					-- bounce off
				local vy = self.object:get_velocity().y
				self.object:set_velocity({x=dir.x*-3,y=vy,z=dir.z*-3})	
					-- play attack sound if defined
				mobkit.make_sound(self,'attack')
				phase=4
			end
		end
	end
	mobkit.queue_low(self,func)
end

function mobkit.lq_fallover(self)
	local zrot = 0
	local init = true
	local func=function(self)
		if init then
			local vel = self.object:get_velocity()
			self.object:set_velocity(mobkit.pos_shift(vel,{y=1}))
			mobkit.animate(self,'stand')
			init = false
		end
		zrot=zrot+pi*0.05
		local rot = self.object:get_rotation()
		self.object:set_rotation({x=rot.x,y=rot.y,z=zrot})
		if zrot >= pi*0.5 then return true end
	end
	mobkit.queue_low(self,func)
end
-----------------------------
-- HIGH LEVEL QUEUE FUNCTIONS
-----------------------------

function mobkit.dumbstep(self,height,tpos,speed_factor)
	if height <= 0.001 then
		mobkit.lq_turn2pos(self,tpos) 
		mobkit.lq_dumbwalk(self,tpos,speed_factor)
	else
		mobkit.lq_turn2pos(self,tpos) 
		mobkit.lq_dumbjump(self,height) 
	end
	mobkit.lq_idle(self,random(1,6))
end

function mobkit.hq_roam(self,prty)
	local func=function(self)
		if mobkit.is_queue_empty_low(self) and self.isonground then
			local pos = mobkit.get_stand_pos(self)
			local neighbor = random(8)

			local height, tpos, liquidflag = mobkit.is_neighbor_node_reachable(self,neighbor)
			if height and not liquidflag then mobkit.dumbstep(self,height,tpos,0.3) end
		end
	end
	mobkit.queue_high(self,func,prty)
end

function mobkit.hq_follow0(self,tgtobj)	-- probably delete this one
	local func = function(self)
		if not tgtobj then return true end
		if mobkit.is_queue_empty_low(self) and self.isonground then
			local pos = mobkit.get_stand_pos(self)
			local opos = tgtobj:get_pos()
			if vector.distance(pos,opos) > 3 then
				local neighbor = mobkit.dir2neighbor(vector.direction(pos,opos))
if not neighbor then return true end		--temp debug
				local height, tpos = mobkit.is_neighbor_node_reachable(self,neighbor)
				if height then mobkit.dumbstep(self,height,tpos)
				else	
					for i=1,4 do --scan left
						height, tpos = mobkit.is_neighbor_node_reachable(self,(8+neighbor-i-1)%8+1)
						if height then mobkit.dumbstep(self,height,tpos)
							break
						end		--scan right
						height, tpos = mobkit.is_neighbor_node_reachable(self,(neighbor+i-1)%8+1)
						if height then mobkit.dumbstep(self,height,tpos)
							break
						end
					end
				end
			else
				mobkit.lq_idle(self,1)
			end
		end
	end
	mobkit.queue_high(self,func,0)
end

function mobkit.hq_follow(self,prty,tgtobj)
	local func = function(self)
		if not mobkit.is_alive(tgtobj) then return true end
		if mobkit.is_queue_empty_low(self) and self.isonground then
			local pos = mobkit.get_stand_pos(self)
			local opos = tgtobj:get_pos()
			if vector.distance(pos,opos) > 3 then
				mobkit.goto_next_waypoint(self,opos)
			else
				mobkit.lq_idle(self,1)
			end
		end
	end
	mobkit.queue_high(self,func,prty)
end

function mobkit.hq_goto(self,prty,tpos)
	local func = function(self)
		if mobkit.is_queue_empty_low(self) and self.isonground then
			local pos = mobkit.get_stand_pos(self)
			if vector.distance(pos,tpos) > 3 then
				mobkit.goto_next_waypoint(self,tpos)
			else
				return true
			end
		end
	end
	mobkit.queue_high(self,func,prty)
end

function mobkit.hq_runfrom(self,prty,tgtobj)
	local init=true
	local timer=6
	local func = function(self)
	
		if not mobkit.is_alive(tgtobj) then return true end
		if init then
			timer = timer-self.dtime
			if timer <=0 or vector.distance(self.object:get_pos(),tgtobj:get_pos()) < 8 then
				mobkit.make_sound(self,'scared')
				init=false
			end
			return
		end
		
		if mobkit.is_queue_empty_low(self) and self.isonground then
			local pos = mobkit.get_stand_pos(self)
			local opos = tgtobj:get_pos()
			if vector.distance(pos,opos) < self.view_range*1.1 then
				local tpos = {x=2*pos.x - opos.x,
								y=opos.y,
								z=2*pos.z - opos.z}
				mobkit.goto_next_waypoint(self,tpos)
			else
				self.object:set_velocity({x=0,y=0,z=0})
				return true
			end
		end
	end
	mobkit.queue_high(self,func,prty)
end

function mobkit.hq_hunt(self,prty,tgtobj)
	local func = function(self)
		if not mobkit.is_alive(tgtobj) then return true end
		if mobkit.is_queue_empty_low(self) and self.isonground then
			local pos = mobkit.get_stand_pos(self)
			local opos = tgtobj:get_pos()
			local dist = vector.distance(pos,opos)
			if dist > self.view_range then
				return true
			elseif dist > 3 then
				mobkit.goto_next_waypoint(self,opos)
			else
				mobkit.hq_attack(self,prty+1,tgtobj)					
			end
		end
	end
	mobkit.queue_high(self,func,prty)
end

function mobkit.hq_warn(self,prty,tgtobj)
	timer=0
	tgttime = 0
	local func = function(self)
		if not mobkit.is_alive(tgtobj) then return true end
		local pos = mobkit.get_stand_pos(self)
		local opos = tgtobj:get_pos()
		local dist = vector.distance(pos,opos)
		
		if dist > 11 then
			return true
		elseif dist < 4 or timer > 12 then						-- too close man
--			mobkit.clear_queue_high(self)
			mobkit.remember(self,'hate',tgtobj:get_player_name())
			mobkit.hq_hunt(self,prty+1,tgtobj)							-- priority
		else
			timer = timer+self.dtime
			if mobkit.is_queue_empty_low(self) then				
				mobkit.lq_turn2pos(self,opos)
			end
			-- make noise in random intervals
			if timer > tgttime then
				mobkit.make_sound(self,'warn')
				-- if self.sounds and self.sounds.warn then
					-- minetest.sound_play(self.sounds.warn, {object=self.object})
				-- end
				tgttime = timer + 1.1 + random()*1.5
			end
		end
	end
	mobkit.queue_high(self,func,prty)
end

function mobkit.hq_die(self)
	local timer = 5
	local start = true
	local func = function(self)
		if start then 
			mobkit.lq_fallover(self) 
			self.brainfunc = function(self) end	-- brain dead as well
			start=false
		end
		timer = timer-self.dtime
		if timer < 0 then self.object:remove() end
	end
	mobkit.queue_high(self,func,100)
end

function mobkit.hq_attack(self,prty,tgtobj)
	local func = function(self)
		if not mobkit.is_alive(tgtobj) then return true end
		if mobkit.is_queue_empty_low(self) then
			local pos = mobkit.get_stand_pos(self)
--			local tpos = tgtobj:get_pos()
			local tpos = mobkit.get_stand_pos(tgtobj)
			local dist = vector.distance(pos,tpos)
			if dist > 3 then 
				return true
			else
				mobkit.lq_turn2pos(self,tpos)
				local height = tgtobj:is_player() and 0.8 or tgtobj:get_luaentity().height*0.6
				if tpos.y+height>pos.y then 
					mobkit.lq_jumpattack(self,tpos.y+height-pos.y,tgtobj) 
				else
					mobkit.lq_dumbwalk(self,mobkit.pos_shift(tpos,{x=random()-0.5,z=random()-0.5}))
				end
			end
		end
	end
	mobkit.queue_high(self,func,prty)
end

function mobkit.hq_liquid_recovery(self,prty)	-- scan for nearest land
	local radius = 1
	local yaw = 0
	local func = function(self)
		if not self.isinliquid then return true end
		local pos=self.object:get_pos()
		local vec = minetest.yaw_to_dir(yaw)
		local pos2 = mobkit.pos_shift(pos,vector.multiply(vec,radius))
		local height, liquidflag = mobkit.get_terrain_height(pos2)
		if height and not liquidflag then
			mobkit.hq_swimto(self,prty,pos2)
			return true
		end
		yaw=yaw+pi*0.25
		if yaw>2*pi then
			yaw = 0
			radius=radius+1
			if radius > self.view_range then	
				self.hp = 0
				return true
			end	
		end
	end
	mobkit.queue_high(self,func,prty)
end

function mobkit.hq_swimto(self,prty,tpos)
	local func = function(self)
--		if not self.isinliquid and mobkit.is_queue_empty_low(self) then return true end
		if not self.isinliquid and self.isonground then return true end
--		local pos = self.object:get_pos()
		local pos = mobkit.get_stand_pos(self)
		local y=self.object:get_velocity().y
		local pos2d = {x=pos.x,y=0,z=pos.z}
		local dir=vector.normalize(vector.direction(pos2d,tpos))
		local yaw = minetest.dir_to_yaw(dir)
		
		if mobkit.timer(self,1) then
--perpendicular vectors: {-z,x};{z,-x}
			local offset=self.collisionbox[1]
			local pos1 = mobkit.pos_shift(mobkit.pos_shift(pos,{x=-dir.z*offset,z=dir.x*offset}),dir)
			local h,l = mobkit.get_terrain_height(pos1)
			if h and h>pos.y then
				mobkit.lq_freejump(self)
			else 
				local pos2 = mobkit.pos_shift(mobkit.pos_shift(pos,{x=dir.z*offset,z=-dir.x*offset}),dir)
				local h,l = mobkit.get_terrain_height(pos2)
				if h and h>pos.y then
					mobkit.lq_freejump(self)
				end
			end
		elseif mobkit.turn2yaw(self,yaw) then
			dir.y = y
			self.object:set_velocity(dir)
		end
	end
	mobkit.queue_high(self,func,prty)
end

---------------------
-- AQUATIC
---------------------

-- MACROS
local function aqua_radar_dumb(pos,yaw,range,reverse)
	range = range or 4
	
	local function okpos(p)
		local node = mobkit.nodeatpos(p)
		if node then 
			if node.drawtype == 'liquid' then 
				local nodeu = mobkit.nodeatpos(mobkit.pos_shift(p,{y=1}))
				local noded = mobkit.nodeatpos(mobkit.pos_shift(p,{y=-1}))
				if (nodeu and nodeu.drawtype == 'liquid') or (noded and noded.drawtype == 'liquid') then
					return true
				else
					return false
				end
			else
				local h,l = mobkit.get_terrain_height(p)
				if h then 
					local node2 = mobkit.nodeatpos({x=p.x,y=h+1.99,z=p.z})
					if node2 and node2.drawtype == 'liquid' then return true, h end
				else
					return false
				end
			end
		else
			return false
		end
	end
	
	local fpos = mobkit.pos_translate2d(pos,yaw,range)
	local ok,h = okpos(fpos)
	if not ok then
		local ffrom, fto, fstep
		if reverse then 
			ffrom, fto, fstep = 3,1,-1
		else
			ffrom, fto, fstep = 1,3,1
		end
		for i=ffrom, fto, fstep  do
			local ok,h = okpos(mobkit.pos_translate2d(pos,yaw+i,range))
			if ok then return yaw+i,h end
			ok,h = okpos(mobkit.pos_translate2d(pos,yaw-i,range))
			if ok then return yaw-i,h end
		end
		return yaw+pi,h
	else 
		return yaw, h
	end	
end

function mobkit.is_in_deep(target)
	if not target then return false end
	local nodepos = mobkit.get_stand_pos(target)
	local node1 = mobkit.nodeatpos(nodepos)
	nodepos.y=nodepos.y+1
	local node2 = mobkit.nodeatpos(nodepos)
	nodepos.y=nodepos.y-2
	local node3 = mobkit.nodeatpos(nodepos)
	if node1 and node2 and node1.drawtype=='liquid' and (node2.drawtype=='liquid' or node3.drawtype=='liquid') then
		return true
	end
end

-- HQ behaviors

function mobkit.hq_aqua_roam(self,prty,speed)
	local tyaw = 0
	local init = true
	local prvscanpos = {x=0,y=0,z=0}
	local center = self.object:get_pos()
	local func = function(self)
		if init then
			mobkit.animate(self, 'swin') --changed by petz
			init = false
		end
		local pos = mobkit.get_stand_pos(self)
		local yaw = self.object:get_yaw()
		local scanpos = mobkit.get_node_pos(mobkit.pos_translate2d(pos,yaw,speed))
		if not vector.equals(prvscanpos,scanpos) then
			prvscanpos=scanpos
			local nyaw,height = aqua_radar_dumb(pos,yaw,speed,true)
			if height and height > pos.y then
				local vel = self.object:get_velocity()
				vel.y = vel.y+1
				self.object:set_velocity(vel)
			end	
			if yaw ~= nyaw then
				tyaw=nyaw
				mobkit.hq_aqua_turn(self,prty+1,tyaw,speed)
				return
			end
		end
		if mobkit.timer(self,1) then
			if vector.distance(pos,center) > abr*16*0.5 then
				tyaw = minetest.dir_to_yaw(vector.direction(pos,{x=center.x+random()*10-5,y=center.y,z=center.z+random()*10-5}))
			else
				if random(10)>=9 then tyaw=tyaw+random()*pi - pi*0.5 end
			end
		end
		
		mobkit.turn2yaw(self,tyaw,3)
		local yaw = self.object:get_yaw()
		mobkit.go_forward_horizontal(self,yaw,speed)
	end
	mobkit.queue_high(self,func,prty)
end

function mobkit.hq_aqua_turn(self,prty,tyaw,speed)
	local func = function(self)
		local finished=mobkit.turn2yaw(self,tyaw)
		local yaw = self.object:get_yaw()
		mobkit.go_forward_horizontal(self,yaw,speed)
		if finished then return true end
	end
	mobkit.queue_high(self,func,prty)
end

function mobkit.hq_aqua_attack(self,prty,tgtobj,speed)
	local tyaw = 0
	local prvscanpos = {x=0,y=0,z=0}
	local init = true
	local tgtbox = tgtobj:get_properties().collisionbox
	local func = function(self)
		if not mobkit.is_alive(tgtobj) then return true end
		if init then
			mobkit.animate(self,'fast')
			mobkit.make_sound(self,'attack')
			init = false
		end
		local pos = mobkit.get_stand_pos(self)
		local yaw = self.object:get_yaw()
		local scanpos = mobkit.get_node_pos(mobkit.pos_translate2d(pos,yaw,speed))
		if not vector.equals(prvscanpos,scanpos) then
			prvscanpos=scanpos
			local nyaw,height = aqua_radar_dumb(pos,yaw,speed*0.5)
			if height and height > pos.y then
				local vel = self.object:get_velocity()
				vel.y = vel.y+1
				self.object:set_velocity(vel)
			end	
			if yaw ~= nyaw then
				tyaw=nyaw
				mobkit.hq_aqua_turn(self,prty+1,tyaw,speed)
				return
			end
		end

		local tpos = tgtobj:get_pos()
		local tyaw=minetest.dir_to_yaw(vector.direction(pos,tpos))	
		mobkit.turn2yaw(self,tyaw,3)
		local yaw = self.object:get_yaw()
		if mobkit.timer(self,1) then
			if not mobkit.is_in_deep(tgtobj) then return true end
			local vel = self.object:get_velocity()
			if tpos.y>pos.y+0.5 then self.object:set_velocity({x=vel.x,y=vel.y+0.5,z=vel.z})
			elseif tpos.y<pos.y-0.5 then self.object:set_velocity({x=vel.x,y=vel.y-0.5,z=vel.z}) end
		end
		if mobkit.is_pos_in_box(mobkit.pos_translate2d(pos,yaw,self.attack.range),tpos,tgtbox) then	--bite
			tgtobj:punch(self.object,1,self.attack)
			mobkit.hq_aqua_turn(self,prty,yaw-pi,speed)
			return true
		end
		mobkit.go_forward_horizontal(self,yaw,speed)
	end
	mobkit.queue_high(self,func,prty)
end

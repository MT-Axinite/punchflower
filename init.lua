minetest.register_privilege("flowerset","Allow player to configure punchflower")
minetest.register_privilege("flowerpunch","Allow player to use punchflower")

local timers = {}
local cooldown = minetest.setting_get("punchflower.cooldown")
if cooldown ~= nil then
	cooldown = tonumber(cooldown)
else
	cooldown = 60
end

local areasize = function(rawschem)
	local idx = rawschem:find(":",1) or 0
	rawschem = rawschem:sub(idx+1, #rawschem )
	local structures = minetest.deserialize(rawschem)
	if structures == nil then
		minetest.debug("deserialization failed on "..rawschem:sub(1,20).." ... ")
		return
	end

	-- iterate to find the greates x,y and z values
	local topx, topy, topz = 0,0,0
	for i,node in pairs(structures) do
		if node.x > topx then topx = node.x end
		if node.y > topy then topy = node.y end
		if node.z > topz then topz = node.z end
	end

	return {x=topx,y=topy,z=topz}
end

local conflabel = "Send"

local schemform = function(slist,sname)
	local fsn = "punchflower:schematic"
	if type(slist) ~= "string" then slist = "" end
	if type(sname) ~= "string" then sname = "" end

	formspeccer:clear(fsn)
	formspeccer:newform(fsn,"7,6")
	formspeccer:add_field(fsn,{name="schems",value=slist,label="Schema possibilities",xy="1,1",wh="5,1"})
	formspeccer:add_field(fsn,{name="areaname",value=sname,label="Area name",xy="1,2",wh="5,1"})
	formspeccer:add_button(fsn,{xy="1,3",wh="5,3",name="submit",label=conflabel},true)
	return formspeccer:to_string(fsn)
end

local openablefile = function(name)
	local path = minetest.get_worldpath() .. "/schems/" .. name
	local fh,err = io.open(path,"r")
	if err then return false end
	fh:close()
	return true
end


local sep = "," -- separater for schemlists

local filecheck = function(datastring,playername)
	local endlist = ""
	for _,schemname in pairs(datastring:split(sep) ) do
		if schemname == "" then
			-- nada.
		elseif openablefile(schemname) then
			endlist = endlist .. sep .. schemname
		else
			minetest.chat_send_player(playername,'Schema file "'..schemname..'" cannot be opened and has been removed.')
		end
	end
	return endlist:sub(2,#endlist) -- wallop initial space
end

local randomschem = function(schemlist)
	if schemlist == nil then return end

	local schems = schemlist:split(sep)
	if #schems < 1 then return end

	return schems[math.random(1,#schems)]
end

local loadschem = function(pos,filename)
	-- extracted from WorldEdit base code
	local path = minetest.get_worldpath() .. "/schems/" .. filename
	minetest.debug("Trying to load schematic "..path)

	pos = {x=pos.x+1,y=pos.y,z=pos.z}

	file, err = io.open(path, "rb")
	if err then return end

	local value = file:read("*a")
	file:close()

	local version = worldedit.read_header(value)
	if version == 0 then
		minetest.debug("File is invalid - "..filename)
		return
	elseif version > worldedit.LATEST_SERIALIZATION_VERSION then
		minetest.debug("File was created with newer version of WorldEdit - "..filename)
		return
	end
	local version = worldedit.read_header(value)
	if version == 0 then
		minetest.debug("File is invalid - "..filename)
		return
	elseif version > worldedit.LATEST_SERIALIZATION_VERSION then
		minetest.debug("File was created with newer version of WorldEdit - "..filename)
		return
	end

	local pos2 = areasize(value)
	if pos2 == nil then return end

	pos2 = {
		x = pos.x+pos2.x,
		y = pos.y+pos2.y,
		z = pos.z+pos2.z,
	}
	-- TODO clear the specified area first
	-- then add the schematic
	worldedit.set(pos,pos2,"air")

	local count = worldedit.deserialize(pos, value)
end

local performreset = function(pos)
	local meta = minetest.get_meta(pos)
	local datastring = meta:get_string("data")
	if datastring == nil then
		minetest.debug("No data artefact on punchflower")
		return
	end
	local filename = randomschem(datastring)
	if filename ~= nil then
		loadschem(pos,filename)
	end
end


local flowerimage = "punchflower.png"
minetest.register_node("punchflower:flower1",{
	tiles = {flowerimage},
	groups = {unbreakable = 1},
	wield_image = flowerimage,
	inventory_image = flowerimage,
	sunlight_propagates = true,
	paramtype = "light",
	drawtype = "plantlike",
	after_place_node = function(pos,placer)
		local meta = minetest.get_meta(pos)
		meta:set_string("formspec",schemform())
	end,
	on_receive_fields = function(pos,formname,fields,player)
		local playername = player:get_player_name()
		if not minetest.check_player_privs(playername, {flowerset=true}) then
			return
		end
		if fields.submit ~= conflabel then return end

		local meta = minetest.get_meta(pos)

		local schems = filecheck(fields.schems,playername)
		meta:set_string("data",schems)
		meta:set_string("areaname",fields.areaname)
		meta:set_string("formspec",schemform(schems,fields.areaname) )

	end,
	on_punch = function(pos,node,puncher,pointed_thing)
		local s_pos = minetest.pos_to_string(pos)
		local lastoperation = 0
		if timers[s_pos] then lastoperation = timers[s_pos] end

		local playername = puncher:get_player_name()
		if not minetest.check_player_privs(playername, {flowerpunch=true}) then
			return
		end

		local calltime = tonumber(os.time() )
		if calltime - lastoperation < cooldown then
			minetest.chat_send_player(playername,"Please wait another "..(cooldown - (calltime-lastoperation) ).."s before resetting !")
			return
		end
		timers[s_pos] = calltime

		performreset(pos)
		local meta = minetest.get_meta(pos)
		local areaname = meta:get_string("areaname")
		if areaname == nil then
			areaname = "an arena"
		end
		minetest.chat_send_all(playername .. " has reset "..areaname.."!")
	end
})

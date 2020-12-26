--[[
#part of the 3DreamEngine by Luke100000
loader.lua - loads objects
--]]

local lib = _3DreamEngine

local function newBoundaryBox()
	return {
		first = vec3(math.huge, math.huge, math.huge),
		second = vec3(-math.huge, -math.huge, -math.huge),
		center = vec3(0.0, 0.0, 0.0),
		size = 0
	}
end

local function clone(t)
	local n = { }
	for d,s in pairs(t) do
		n[d] = s
	end
	return n
end

--add to object library instead
function lib:loadLibrary(path, shaderType, args, prefix)
	if type(shaderType) == "table" then
		return self:loadLibrary(path, shaderType and shaderType.shaderType, shaderType)
	end
	args = table.copy(args) or { }
	args.shaderType = shaderType or args.shaderType
	
	prefix = prefix or ""
	
	args.no3doRequest = true
	args.loadAsLibrary = true
	
	--load
	local obj = self:loadObject(path, shaderType, args)
	
	--insert into library
	local overwritten = { }
	for name,o in pairs(obj.objects) do
		local id = prefix .. o.name
		if not overwritten[id] then
			overwritten[id] = true
			self.objectLibrary[id] = { }
		end
		table.insert(self.objectLibrary[id], o)
	end
	
	--insert collisions into library
	local overwritten = { }
	if obj.collisions then
		for name,c in pairs(obj.collisions) do
			local id = prefix .. c.name
			if not overwritten[id] then
				overwritten[id] = true
				self.collisionLibrary[id] = { }
			end
			table.insert(self.collisionLibrary[id], c)
		end
	end
	
	--insert physics into library
	local overwritten = { }
	if obj.physics then
		for name,c in pairs(obj.physics) do
			local id = prefix .. c.name
			if not overwritten[id] then
				overwritten[id] = true
				self.physicsLibrary[id] = { }
			end
			table.insert(self.physicsLibrary[id], c)
		end
	end
end

--remove objects without vertices
local function cleanEmpties(obj)
	for d,o in pairs(obj.objects) do
		if o.vertices and #o.vertices == 0 and not o.linked then
			obj.objects[d] = nil
		end
	end
end

--loads an object
--args is a table containing additional settings
--path is the absolute path without extension
--3do objects will be loaded part by part, threaded. yourObject.objects.yourMesh.mesh is nil, if its not loaded yet
function lib:loadObject(path, shaderType, args)
	if type(shaderType) == "table" then
		return self:loadObject(path, shaderType and shaderType.shaderType, shaderType)
	end
	args = table.copy(args) or { }
	args.shaderType = shaderType or args.shaderType
	
	--some shaderType specific settings
	if args.shaderType then
		local dat = self.shaderLibrary.base[args.shaderType]
		if args.splitMaterials == nil then
			args.splitMaterials = dat.splitMaterials
		end
	end
	
	local supportedFiles = {
		"mtl", --obj material file
		"mat", --3DreamEngine material file
		"3do", --3DreamEngine object file - way faster than obj but does not keep vertex information
		"vox", --magicka voxel
		"obj", --obj file
		"dae", --dae file
	}
	
	local obj = self:newObject(path)
	obj.args = args
	
	--load files
	--if two object files are available (.obj and .vox) it might crash, since it loads all)
	local found = false
	for _,typ in ipairs(supportedFiles) do
		local info = love.filesystem.getInfo(obj.path .. "." .. typ)
		if info then
			--check if 3do is up to date
			if typ == "3do" then
				if args.skip3do then
					goto skip
				end
				
				local info2 = love.filesystem.getInfo(obj.path .. ".obj")
				if info2 and info2.modtime > info.modtime then
					goto skip
				end
				
				local info2 = love.filesystem.getInfo(obj.path .. ".dae")
				if info2 and info2.modtime > info.modtime then
					goto skip
				end
			end
			
			found = true
			
			--load object
			local failed = self.loader[typ](self, obj, obj.path .. "." .. typ)
			
			--skip furhter modifying and exporting if already packed as 3do
			--also skips mesh loading since it is done manually
			if typ == "3do" and not failed then
				break
			end
		end
		::skip::
	end
	
	if not found then
		error("object " .. obj.name .. " not found (" .. obj.path .. ")")
	end
	
	
	--remove empty objects
	cleanEmpties(obj)
	
	
	--parse tags
	local tags = {
		["COLLPHY"] = true,
		["COLLISION"] = true,
		["PHYSICS"] = true,
		["LOD"] = true,
		["POS"] = true,
		["LINK"] = true,
		["BAKE"] = true,
		["SHADOW"] = true,
	}
	for d,o in pairs(obj.objects) do
		o.tags = { }
		local possibles = string.split(o.name, "_")
		for index,tag in ipairs(possibles) do
			local key, value = unpack(string.split(tag, ":"))
			if tags[key] then
				o.tags[key:lower()] = value or true
			else
				if key:upper() == key and key:lower() ~= key then
					print("unknown tag '" .. key .. "' of object '" .. o.name .. "' in '" .. path .. "'?")
				end
				o.name = table.concat(possibles, "_", index)
				break
			end
		end
	end
	
	
	--extract positions
	for d,o in pairs(obj.objects) do
		if o.tags.pos then
			--average position
			local x, y, z = 0, 0, 0
			for i,v in ipairs(o.vertices) do
				x = x + v[1]
				y = y + v[2]
				z = z + v[3]
			end
			local c = #o.vertices
			x = x / c
			y = y / c
			z = z / c
			
			--average size
			local r = 0
			for i,v in ipairs(o.vertices) do
				r = r + math.sqrt((v[1] - x)^2 + (v[2] - y)^2 + (v[3] - z)^2)
			end
			r = r / c
			
			--add position
			obj.positions[#obj.positions+1] = {
				name = o.name,
				size = r,
				x = x,
				y = y,
				z = z,
			}
			obj.objects[d] = nil
		end
	end
	
	--detect links
	local linkedNames = { }
	for d,o in pairs(obj.objects) do
		if o.tags.link then
			--remove original
			obj.objects[d] = nil
			
			if not linkedNames[o.name] then
				linkedNames[o.name] = true
				local source = o.linked or (o.name:match("(.*)%.[^.]+") or o.name)
				
				--store link
				obj.linked = obj.linked or { }
				obj.linked[#obj.linked+1] = {
					source = source,
					transform = o.transform
				}
			end
		end
	end
	
	
	--split materials
	local changes = true
	while changes do
		changes = false
		for d,o in pairs(obj.objects) do
			if obj.args.splitMaterials and not o.tags.bake and not o.tags.split then
				changes = true
				obj.objects[d] = nil
				for i,m in ipairs(o.materials) do
					local d2 = d .. "_" .. m.name
					if not obj.objects[d2] then
						local o2 = o:clone()
						o2.group = d
						o2.tags = table.copy(o.tags)
						o2.tags.split = true
						
						o2.material = m
						o2.translation = { }
						
						o2.vertices = { }
						o2.normals = { }
						o2.texCoords = { }
						o2.colors = { }
						o2.materials = { }
						o2.faces = { }
						
						obj.objects[d2] = o2
					end
					
					local o2 = obj.objects[d2]
					
					local i2 = #o2.vertices+1
					o2.vertices[i2] = o.vertices[i]
					o2.normals[i2] = o.normals[i]
					o2.texCoords[i2] = o.texCoords[i]
					o2.colors[i2] = o.colors[i]
					o2.materials[i2] = o.materials[i]
					o2.translation[i] = i2
				end
				
				for i,f in ipairs(o.faces) do
					--TODO: if a face shares more than one material it will cause errors
					local m = o.materials[f[1]]
					local d2 = d .. "_" .. m.name
					local o2 = obj.objects[d2]
					o2.faces[#o2.faces+1] = {
						o2.translation[f[1]],
						o2.translation[f[2]],
						o2.translation[f[3]],
					}
				end
			end
		end
		for d,o in pairs(obj.objects) do
			o.translation = nil
		end
	end
	
	
	--link objects
	if obj.linked then
		for id, link in ipairs(obj.linked) do
			local lo = self.objectLibrary[link.source]
			assert(lo, "linked object " .. link.source .. " is not in the object library!")
			
			--link
			for d,no in ipairs(lo) do
				local co = self:newLinkedObject(no)
				co.transform = link.transform
				co.linked = link.source
				co.name = "link_" .. id .. "_" .. co.name
				obj.objects["link_" .. id .. "_" .. d .. "_" .. no.name] = co
			end
			
			--link collisions
			local lc = self.collisionLibrary[link.source]
			if lc then
				obj.collisions = obj.collisions or { }
				for d,no in ipairs(lc) do
					local co = clone(no)
					co.linkTransform = link.transform
					co.linked = link.source
					obj.collisions["link_" .. id .. "_" .. d .. "_" .. no.name] = co
				end
			end
			
			--link physics
			local lc = self.physicsLibrary[link.source]
			if lc then
				obj.physics = obj.physics or { }
				for d,no in ipairs(lc) do
					local co = clone(no)
					co.transform = link.transform
					co.linked = link.source
					obj.physics["link_" .. id .. "_" .. d .. "_" .. no.name] = co
				end
			end
		end
	end
	
	
	--shadow only detection
	for d,o in pairs(obj.objects) do
		if o.tags.shadow then
			o:setVisibility(false, true, false)
		end
		
		--hide rest of group in shadow pass
		for d2,o2 in pairs(obj.objects) do
			if o2.name == o.name and not o.tags.shadow then
				o:setVisibility(true, false, true)
			end
		end
	end
	
	
	--LOD detection
	for _,typ in ipairs({"render", "shadows", "reflections"}) do
		local max = { }
		for d,o in pairs(obj.objects) do
			if (not o.visibility or o.visibility[typ]) and o.tags.lod then
				local nr = tonumber(o.tags.lod)
				assert(nr, "LOD nr malformed: " .. o.name .. " (use 'LOD:integer')")
				max[o.name] = math.max(max[o.name] or 0, nr)
			end
		end
		
		--apply LOD level
		for d,o in pairs(obj.objects) do
			if (not o.visibility or o.visibility[typ]) and max[o.name] then
				local nr = tonumber(o.tags.lod) or 0
				o:setLOD(nr, max[o.name] == nr and math.huge or nr+1)
			end
		end
	end
	
	
	--create particle systems
	if not obj.args.noParticleSystem then
		self:addParticlesystems(obj)
	end
	
	
	--remove empty objects (second pass)
	cleanEmpties(obj)
	
	
	--calculate bounding box
	if not obj.boundingBox then
		for d,s in pairs(obj.objects) do
			if not s.boundingBox then
				s.boundingBox = newBoundaryBox()
				
				--get aabb
				for i,v in ipairs(s.vertices) do
					local pos = vec3(v)
					s.boundingBox.first = s.boundingBox.first:min(pos)
					s.boundingBox.second = s.boundingBox.second:max(pos)
				end
				s.boundingBox.center = (s.boundingBox.second + s.boundingBox.first) / 2
				
				--get size
				local max = 0
				local c = s.boundingBox.center
				for i,v in ipairs(s.vertices) do
					local pos = vec3(v) - c
					max = math.max(max, pos:lengthSquared())
				end
				s.boundingBox.size = math.max(math.sqrt(max), s.boundingBox.size)
			end
		end
		
		--calculate total bounding box
		obj.boundingBox = newBoundaryBox()
		for d,s in pairs(obj.objects) do
			local sz = vec3(s.boundingBox.size, s.boundingBox.size, s.boundingBox.size)
			
			obj.boundingBox.first = s.boundingBox.first:min(obj.boundingBox.first - sz)
			obj.boundingBox.second = s.boundingBox.second:max(obj.boundingBox.second + sz)
			obj.boundingBox.center = (obj.boundingBox.second + obj.boundingBox.first) / 2
		end
		
		for d,s in pairs(obj.objects) do
			local o = s.boundingBox.center - obj.boundingBox.center
			obj.boundingBox.size = math.max(obj.boundingBox.size, s.boundingBox.size + o:lengthSquared())
		end
	end
	
	
	--get group center
	local center = { }
	local centerCount = { }
	for d,o in pairs(obj.objects) do
		local id = o.LOD_group or o.name
		center[id] = (center[id] or vec3(0, 0, 0)) + o.boundingBox.center
		centerCount[id] = (centerCount[id] or 0) + 1
	end
	for d,o in pairs(obj.objects) do
		local id = o.LOD_group or o.name
		o.LOD_center = center[id] / centerCount[id]
	end
	
	
	--extract collisions
	for d,o in pairs(obj.objects) do
		if o.tags.collision or o.tags.physics or o.tags.collphy then
			if o.vertices then
				--leave at origin for library entries
				if obj.args.loadAsLibrary then
					o.transform = nil
				end
				
				--3D collision
				if o.tags.collision or o.tags.collphy then
					obj.collisions = obj.collisions or { }
					obj.collisionCount = (obj.collisionCount or 0) + 1
					obj.collisions[d] = self:getCollisionData(o)
				end
				
				--2.5D physics
				if o.tags.physics or o.tags.collphy then
					obj.physics = obj.physics or { }
					obj.physics[d] = self:getPhysicsData(o)
				end
			end
			
			--remove if no longer used
			--TODO: pfusch
			local count = 0
			for d,s in pairs(o.tags) do
				if d ~= "split" then
					count = count + 1
				end
			end
			if count <= 1 then
				obj.objects[d] = nil
			end
		end
	end
	
	
	--post load materials
	for d,s in pairs(obj.materials) do
		s.dir = s.dir or obj.args.textures or obj.dir
		self:finishMaterial(s, obj)
	end
	
	
	--bake
	for d,o in pairs(obj.objects) do
		if o.tags.bake then
			self:bakeMaterial(o)
		end
	end
	
	
	--create meshes
	if not obj.args.noMesh then
		local cache = { }
		for d,o in pairs(obj.objects) do
			if not o.linked then
				if cache[o.vertices] then
					o.mesh = cache[o.vertices].mesh
					o.tangents = cache[o.vertices].tangents
				else
					self:createMesh(o)
					cache[o.vertices] = o
				end
			end
		end
	end
	
	
	--cleaning up
	if obj.args.cleanup ~= false then
		for d,s in pairs(obj.objects) do
			if obj.args.cleanup then
				--clean important data only on request to allow reusage for collision data
				s.vertices = nil
				s.faces = nil
				s.normals = nil
			end
			
			--cleanup irrelevant data
			s.texCoords = nil
			s.colors = nil
			s.materials = nil
			s.extras = nil
			
			s.tangents = nil
		end
	end
	
	--3do exporter
	if obj.args.export3do then
		self:export3do(obj)
	end
	
	return obj
end

lib.meshTypeFormats = {
	textured = {
		{"VertexPosition", "float", 4},     -- x, y, z, extra
		{"VertexTexCoord", "float", 2},     -- UV
		{"VertexNormal", "byte", 4},        -- normal
		{"VertexTangent", "byte", 4},       -- normal tangent
	},
	textured_array = {
		{"VertexPosition", "float", 4},     -- x, y, z, extra
		{"VertexTexCoord", "float", 3},     -- UV
		{"VertexNormal", "byte", 4},        -- normal
		{"VertexTangent", "byte", 4},       -- normal tangent
	},
	simple = {
		{"VertexPosition", "float", 4},     -- x, y, z, extra
		{"VertexTexCoord", "float", 3},     -- normal
		{"VertexMaterial", "float", 3},     -- specular, glossiness, emissive
		{"VertexColor", "byte", 4},         -- color
	},
	material = {
		{"VertexPosition", "float", 4},     -- x, y, z, extra
		{"VertexTexCoord", "float", 3},     -- normal
		{"VertexMaterial", "float", 1},     -- material
	},
}

--takes an final and face table and generates the mesh and vertexMap
--note that .3do files has it's own mesh loader
function lib.createMesh(self, o)
	--set up vertex map
	local vertexMap = { }
	for d,f in ipairs(o.faces) do
		vertexMap[#vertexMap+1] = f[1]
		vertexMap[#vertexMap+1] = f[2]
		vertexMap[#vertexMap+1] = f[3]
	end
	
	--calculate vertex normals and uv normals
	local shader = self.shaderLibrary.base[o.shaderType]
	assert(shader, "shader '" .. tostring(o.shaderType) .. "' for object '" .. tostring(o.name) .. "' does not exist")
	if shader.requireTangents then
		self:calcTangents(o)
	end
	
	--create mesh
	local meshLayout = table.copy(self.meshTypeFormats[o.meshType])
	o.mesh = love.graphics.newMesh(meshLayout, #o.vertices, "triangles", "static")
	
	--vertex map
	o.mesh:setVertexMap(vertexMap)
	
	--set vertices
	local empty = {1, 0, 1, 1}
	for i = 1, #o.vertices do
		local vertex = o.vertices[i] or empty
		local normal = o.normals[i] or empty
		local texCoord = o.texCoords[i] or empty
		
		if o.meshType == "textured" then
			local tangent = o.tangents[i] or empty
			o.mesh:setVertex(i,
				vertex[1], vertex[2], vertex[3], o.extras[i] or 1,
				texCoord[1], texCoord[2],
				normal[1]*0.5+0.5, normal[2]*0.5+0.5, normal[3]*0.5+0.5, 0.0,
				tangent[1]*0.5+0.5, tangent[2]*0.5+0.5, tangent[3]*0.5+0.5, tangent[4] or 0.0
			)
		elseif o.meshType == "textured_array" then
			local tangent = o.tangents[i] or empty
			o.mesh:setVertex(i,
				vertex[1], vertex[2], vertex[3], o.extras[i] or 1,
				texCoord[1], texCoord[2], texCoord[3], 
				normal[1]*0.5+0.5, normal[2]*0.5+0.5, normal[3]*0.5+0.5, 0.0,
				tangent[1]*0.5+0.5, tangent[2]*0.5+0.5, tangent[3]*0.5+0.5, tangent[4] or 0.0
			)
		elseif o.meshType == "simple" then
			local material = o.materials[i] or empty
			local color = o.colors[i] or material.color or empty
			
			local specular = material.specular or material[1] or 0
			local glossiness = material.glossiness or material[2] or 0
			local emission = material.emission or material[3] or 0
			if type(emission) == "table" then
				emission = emission[1] / 3 + emission[2] / 3 + emission[3] / 3
			end
			
			o.mesh:setVertex(i,
				vertex[1], vertex[2], vertex[3], o.extras[i] or 1,
				normal[1], normal[2], normal[3],
				specular, glossiness, emission,
				color[1], color[2], color[3], color[4]
			)
		elseif o.meshType == "material" then
			o.mesh:setVertex(i,
				vertex[1], vertex[2], vertex[3], o.extras[i] or 1,
				normal[1], normal[2], normal[3],
				texCoord
			)
		end
	end
end
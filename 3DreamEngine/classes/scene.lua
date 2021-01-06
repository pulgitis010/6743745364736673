local lib = _3DreamEngine

local white = vec4(1.0, 1.0, 1.0, 1.0)

--harcoded distance after center transformation minus the camPos
local function getDistance( b, transform)
	local camPos = dream.cam.pos or vec3(0, 0, 0)
	return transform and (
		(transform[1] * b[1] + transform[2] * b[2] + transform[3] * b[3] + transform[4] - camPos[1])^2 +
		(transform[5] * b[1] + transform[6] * b[2] + transform[7] * b[3] + transform[8] - camPos[2])^2 +
		(transform[9] * b[1] + transform[10] * b[2] + transform[11] * b[3] + transform[12] - camPos[3])^2
	) or (b - camPos):lengthSquared()
end

function lib:newScene()
	local m = setmetatable({ }, self.meta.scene)
	m:clear()
	return m
end

return {
	link = {"scene", "visibility"},
	
	clear = function(self)
		--static tasks
		self.tasks = {
			{ --static
				all = { },
				render = { },
				shadows = { },
				reflections = { },
			},
			{ --dynamic
				all = { },
				render = { },
				shadows = { },
				reflections = { },
			},
		}
		
		self.instances = { }
	end,
	
	addObject = function(self, object, parentTransform, col, dynamic)
		if object.groups then
			--object
			for name,group in pairs(object.groups) do
				--apply transformation
				local transform
				if parentTransform then
					if group.transform then
						transform = parentTransform * group.transform
					else
						transform = parentTransform
					end
				elseif group.transform then
					transform = group.transform
				end
				
				--task
				if group.hasLOD then
					local dist = getDistance(group.boundingBox.center, transform)
					for _,o in ipairs(group.objects) do
						local LOD_min, LOD_max = o:getScaledLOD()
						local aDist = LOD_min and o.LOD_center and getDistance(o.boundingBox.center, transform) or dist
						if not LOD_min or aDist >= LOD_min^2 and aDist <= LOD_max^2 then
							self:add(o, transform, col, dynamic)
						end
					end
				else
					for _,o in ipairs(group.objects) do
						self:add(o, transform, col, dynamic)
					end
				end
			end
		else
			--direct subobject
			self:add(object, parentTransform, col, dynamic)
		end
	end,
	
	add = function(self, s, transform, col, dynamic)
		if not self.instances[s] then
			local tasks = { }
			self.instances[s] = tasks
			
			--material shadow override
			local noShadow = s.material.shadow == false
			
			--insert into respective rendering queues
			local visibility = s.visibility or s.obj.visibility
			local dyn = (dynamic or s.dynamic) and 2 or 1
			if visibility then
				if visibility.render then
					self.tasks[dyn].render[s] = tasks
				end
				if visibility.shadows and not noShadow then
					self.tasks[dyn].shadows[s] = tasks
				end
				if visibility.reflections then
					self.tasks[dyn].reflections[s] = tasks
				end
			elseif noShadow then
				self.tasks[dyn].render[s] = tasks
				self.tasks[dyn].reflections[s] = tasks
			else
				self.tasks[dyn].all[s] = tasks
			end
		end
		
		--create and insert task
		local task = setmetatable({col or white, transform, false, false, s.obj.boneTransforms}, lib.meta.task)
		table.insert(self.instances[s], task)
	end,
}
local lib = _3DreamEngine

local class = { }

function class:setPixelShader(shader)
	if self.class == "object" then
		for d,s in pairs(self.objects) do
			s:setPixelShader(shader)
		end
		
		for d,s in pairs(self.meshes) do
			s:setPixelShader(shader)
		end
	else
		shader = lib:resolveShaderName(shader)
		assert(shader.type == "pixel", "invalid shader type")
		self.pixelShader = shader
		
		if self.initShaders then
			self:initShaders()
		end
	end
end

function class:setVertexShader(shader)
	if self.class == "object" then
		for d,s in pairs(self.objects) do
			s:setVertexShader(shader)
		end
		
		for d,s in pairs(self.meshes) do
			s:setVertexShader(shader)
		end
	else
		shader = lib:resolveShaderName(shader)
		assert(shader.type == "vertex", "invalid shader type")
		self.vertexShader = shader
		
		if self.initShaders then
			self:initShaders()
		end
	end
end

function class:setWorldShader(shader)
	if self.class == "object" then
		for d,s in pairs(self.objects) do
			s:setWorldShader(shader)
		end
		
		for d,s in pairs(self.meshes) do
			s:setWorldShader(shader)
		end
	else
		shader = lib:resolveShaderName(shader)
		assert(shader.type == "world", "invalid shader type")
		self.worldShader = shader
		
		if self.initShaders then
			self:initShaders()
		end
	end
end

return class
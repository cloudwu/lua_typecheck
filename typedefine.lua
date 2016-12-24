local supported_type = {
	type_map = true,
	type_enum = true,
	type_array = true,
	type_undefined = true,
	type_struct = true,
	type_internal = true,
	type_object = true,
}

local internal_type = { number = true, string = true, boolean = true }

local function type_tostring(self)
	return self._typename
end

-------- type internal (number/string/boolean)

local internal_mt = { __metatable = "type_internal", __tostring = type_tostring }; internal_mt.__index = internal_mt

local function gen_type(v)
	return setmetatable({ _default = v , _typename = type(v) }, internal_mt)
end

function internal_mt:__call(v)
	if v ~= nil then
		if type(v) ~= self._typename then
			error("type mismatch " .. tostring(v) .. " is not " .. self._typename)
		end
		return v
	else
		return self._default
	end
end

function internal_mt:verify(v)
	if type(v) == self._typename then
		return true
	else
		return false, "type mismatch " .. tostring(v) .. " is not " .. self._typename
	end
end

-------- type enum

local enum_mt = { __metatable = "type_enum" , __tostring = type_tostring }; enum_mt.__index = enum_mt

function enum_mt:__call(v)
	if v == nil then
		return self._default
	else
		assert(self[v] == true, "Invalid enum value")
		return v
	end
end

function enum_mt:verify(v)
	if self[v] == true then
		return true
	else
		return false, "Invalid enum value " .. tostring(v)
	end
end

local function new_enum(enums)
	assert(type(enums) == "table", "Invalid enum")
	local enum_obj = { _default = enums[1] , _typename = "enum" }
	for idx,v in ipairs(enums) do
		assert(type(v) == "string" and enum_obj[v] == nil, "Invalid enum value")
		enum_obj[v] = true
	end
	return setmetatable(enum_obj, enum_mt)
end

----------- type object

local object_mt = { __metatable = "type_object" , __tostring = type_tostring }; object_mt.__index = object_mt

function object_mt:__call(obj)
	assert(self:verify(obj))
	return obj
end

function object_mt:verify(v)
	if v == nil then
		return true
	end
	local t = type(v)
	if t == "table" or t == "userdata" then
		return true
	end

	return false, "Not an object " .. tostring(v)
end

---------- type array

local array_mt = { __metatable = "type_array", __tostring = type_tostring }; array_mt.__index = array_mt

function array_mt:__call(init)
	if init == nil then
		return {}
	else
		local array = {}
		local t = self._array
		for idx, v in ipairs(init) do
			assert(t:verify(v))
			array[idx] = t(v)
		end
		return array
	end
end

function array_mt:verify(obj)
	if type(obj) ~= "table" then
		return false, "Not an table"
	else
		local t = self._array
		local max
		for idx, v in ipairs(obj) do
			local ok, err = t:verify(v)
			if not ok then
				return ok, err
			end
			max = idx
		end
		for k in pairs(obj) do
			if type(k) ~= "number" then
				return false, "Invalid key " .. tostring(k)
			end
			local nk = math.tointeger(k)
			if nk == nil or nk <=0 or nk > max then
				return false, "Invalid key " .. tostring(nk)
			end
		end
		return true
	end
end

local function new_array(t)
	assert(supported_type[getmetatable(t)], "Need a type for array")
	return setmetatable({ _typename = "array of " .. tostring(t) , _array = t }, array_mt)
end

-------------- type map
local map_mt = { __metatable = "type_map", __tostring = type_tostring }; map_mt.__index = map_mt

function map_mt:__call(init)
	if init == nil then
		return {}
	else
		local map = {}
		local keyt = self._key
		local valuet = self._value
		for k, v in pairs(init) do
			assert(keyt:verify(k))
			assert(valuet:verify(v))
			map[keyt(k)] = valuet(v)
		end
		return map
	end
end

function map_mt:verify(obj)
	if type(obj) ~= "table" then
		return false, "Not an table"
	else
		local keyt = self._key
		local valuet = self._value
		for k,v in pairs(obj) do
			local ok, err = keyt:verify(k)
			if not ok then
				return false, string.format("Invalid key %s : %s", k, err)
			end
			local ok, err = valuet:verify(v)
			if not ok then
				return false, string.format("Invalid value %s : %s", k, err)
			end
		end
		return true
	end
end

local function new_map(key, value)
	assert(supported_type[getmetatable(key)], "Need a type for key")
	assert(supported_type[getmetatable(value)], "Need a type for value")
	return setmetatable({ _typename = string.format("map of %s:%s", key, value) , _key = key, _value = value }, map_mt)
end

---------------------

local types = {
	enum = new_enum,
	array = new_array,
	map = new_map,
	object = setmetatable({ _typename = "object" }, object_mt),
}

for _,v in ipairs{0, false, ""} do
	types[type(v)] = gen_type(v)
end

local struct_mt = { __metatable = "type_struct" , __tostring = type_tostring }; struct_mt.__index = struct_mt

function struct_mt:__call(init)
	local obj = {}
	local meta = self._types
	local default = self._defaults
	if init then
		for k,type_obj in pairs(meta) do
			local v = init[k]
			if v == nil then
				v = default[k]
			end
			obj[k] = type_obj(v)
		end
		for k,v in pairs(init) do
			if not meta[k] then
				error(tostring(k) .. " is not a valid key")
			end
		end
	else
		for k,type_obj in pairs(meta) do
			local v = default[k]
			obj[k] = type_obj(v)
		end
	end
	return obj
end

function struct_mt:verify(obj)
	local t = self._types
	if type(obj) ~= "table" then
		return false, "Is not a table"
	end
	for k,v in pairs(obj) do
		local meta = t[k]
		if not meta then
			return false, "Invalid key : " .. tostring(k)
		end
	end
	for k,meta in pairs(t) do
		local v = obj[k]
		local ok, err = meta:verify(v)
		if not ok then
			return false, string.format("Type mismatch : %s should be %s (%s)", k, meta, err)
		end
	end
	return true
end

local function create_type(proto, t)
	t._defaults = {}
	t._types = {}
	for k,v in pairs(proto) do
		t._defaults[k] = v
		local vt = type(v)
		if internal_type[vt] then
			t._types[k] = types[vt]
		elseif vt == "table" and supported_type[getmetatable(v)] then
			t._types[k] = v
			t._defaults[k] = nil
		else
			error("Unsupport type " .. tostring(k) .. ":" .. tostring(v))
		end
	end
	return setmetatable(t, struct_mt)
end

function types.struct(proto)
	assert(type(proto) == "table", "Invalid type proto")
	return create_type(proto, { _typename = "anonymous struct"})
end

local function define_type(_, typename, proto)
	local t = rawget(types,typename)
	if t == nil then
		t = {}
	elseif getmetatable(t) == "type_undefined" then
		debug.setmetatable(t, nil)
	else
		error("Redefined type " .. tostring(typename))
	end
	assert(type(proto) == "table", "Invalid type proto")
	local pt = getmetatable(proto)
	if pt == nil then
		proto = create_type(proto, t)
	elseif not supported_type[pt] then
		error("Invalid proto meta " .. pt)
	end
	proto._typename = typename
	types[typename] = proto
end

local function undefined_error(self)
	error(self._typename .. " is undefined")
end

local undefined_type_mt = {
	__call = undefined_error,
	verify = undefined_error,
	__metatable = "type_undefined",
	__tostring = function(self)
		return "undefined " .. self._typename
	end,
}

undefined_type_mt.__index = undefined_type_mt

local function create_undefined_type(_, typename)
	local type_obj = setmetatable({ _typename = typename } , undefined_type_mt)
	types[typename] = type_obj
	return type_obj
end

setmetatable(types, { __index = create_undefined_type })

return setmetatable({}, {
	__index = types,
	__newindex = define_type,
})

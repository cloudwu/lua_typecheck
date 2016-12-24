local td = require "typedefine"

td.e = td.enum { "XXX", "YYY" }

td.foo = {
	x = td.number,
	y = 1,
	z = td.enum { "a", "b", "c" },
	obj = td.object,	-- a ref to lua object (table/userdata)
	a = td.array(td.e),
	m = td.map(td.string, td.number),
	s = td.struct {	-- anonymous struct
		alpha = false,
		beta = true,
	},
}

local foo = td.foo {
	a = { "XXX", "XXX" },
	m = {
		x = 1,
		y = 2,
	},
	z = "c",
	obj = td.foo,
	s = { alpha = true },
}

assert(foo.x == 0)	-- default number is 0
assert(foo.y == 1)	-- default 1
assert(foo.z == "c")
assert(foo.a[1] == "XXX")
assert(foo.m.x == 1)
assert(foo.m.y == 2)
assert(foo.obj == td.foo)	-- a type
assert(foo.s.alpha == true)
assert(foo.s.beta == true)

foo.z = "d"	-- invalid enum
print(td.foo:verify(foo))
foo.z = nil
print(td.foo:verify(foo))
foo.z = "a"
assert(td.foo:verify(foo))


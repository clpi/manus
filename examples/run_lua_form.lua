-- Lua-form @run showcase: the `--- @run` comment harness injects C at compile
-- time, identical to the `.duo` `@run` directive. Parsed in Lua compat mode.

--- @c.include("stdio.h")

-- Inject a C declaration plus an accessor so we can read it from Lua via @c.call
-- without referencing the raw C symbol as a Lua global.
--- @run("printf 'static int from_lua_form = 91; static int get_lf(void){ return from_lua_form; }'")

print("lua-form @run:")
@c.call("printf", "  from_lua_form = %d\n", @c.call("get_lf"))
print("  directive form ok")

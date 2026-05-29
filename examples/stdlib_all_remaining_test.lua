-- Comprehensive test of all remaining global and module standard library functions in Duo

print("--- Testing new Global functions ---")

-- 1. unpack
local tbl = { "one", "two", "three" }
local first_val = unpack(tbl)
print("unpack(tbl):", first_val)
assert(first_val == "one", "unpack failed")

-- 2. setmetatable / getmetatable
local mt = { __tostring = function() return "custom" end }
local t = {}
setmetatable(t, mt)
assert(getmetatable(t) == mt, "setmetatable/getmetatable failed")
print("setmetatable/getmetatable: ok")

-- 3. rawget / rawset / rawlen / rawequal
local rt = {}
rawset(rt, 1, "val")
local val = rawget(rt, 1)
print("rawget:", val)
assert(val == "val", "rawget/rawset failed")

local str_len = rawlen("Duo")
local tbl_len = rawlen(rt)
print("rawlen('Duo'):", str_len)
print("rawlen(rt):", tbl_len)
assert(str_len == 3, "rawlen on string failed")
assert(tbl_len == 1, "rawlen on table failed")

local eq_res = rawequal(rt, rt)
print("rawequal(rt, rt):", eq_res)
assert(eq_res == true, "rawequal failed")

-- 4. collectgarbage
local gc_res = collectgarbage("count")
print("collectgarbage:", gc_res)
assert(type(gc_res) == "number" and gc_res >= 0, "collectgarbage failed")

-- 5. warn
warn("This is a Duo warning!")

-- 6. xpcall
local function buggy()
    return "ok"
end
local function handler()
    return "err"
end
local xp_ok = xpcall(buggy, handler, "arg")
print("xpcall success:", xp_ok)
assert(xp_ok == true, "xpcall failed")

-- 7. load / loadfile / dofile
local lf, lerr = load("return 42")
assert(lf, lerr or "load failed")
assert(lf() == 42, "load chunk failed")

local chunk_file = "duo_load_test_chunk.lua"
local wf = io.open(chunk_file, "w")
assert(wf, "failed to create chunk file")
wf:write("return 43")
wf:close()

local lf2, lerr2 = loadfile(chunk_file)
assert(lf2, lerr2 or "loadfile returned nil")
assert(lf2() == 43, "loadfile chunk failed")

local df_res = dofile(chunk_file)
assert(df_res == 43, "dofile failed")
os.remove(chunk_file)
print("load/loadfile/dofile: ok")

print("\n--- Testing Module Extras ---")

-- 8. coroutine.close
local co = coroutine.create(function() return 42 end)
local close_ok = coroutine.close(co)
print("coroutine.close:", close_ok)
assert(close_ok == true, "coroutine.close failed")

-- 9. package.searchpath
local path_res = package.searchpath("mymod", "./?.lua")
print("package.searchpath:", path_res)
assert(path_res == nil, "package.searchpath should return nil when module not found")

-- 10. string.pack / unpack / packsize / gmatch / dump
local packed = string.pack("i", 42)
local unpacked = string.unpack("i", packed)
local psize = string.packsize("i")
local gm = string.gmatch("hello", ".*")
local dmp = string.dump(function() end)

print("string.packsize:", psize)
print("string.unpack:", unpacked)
local gm_first = gm()
print("string.gmatch first:", gm_first)
print("string.dump:", dmp)

assert(psize == 4, "string.packsize failed")
assert(unpacked == 42, "string.unpack failed")
assert(gm_first == "hello", "string.gmatch failed")

-- 11. io.input / io.output / io.type / io.popen / seek / flush
print("\n--- Testing Advanced IO features ---")
local test_filename = "duo_io_test_temp.txt"
local test_file = io.open(test_filename, "w")
assert(test_file ~= nil, "io.open failed")

local io_t1 = io.type(test_file)
print("io.type of open file:", io_t1)
assert(io_t1 == "file", "io.type open failed")

test_file:write("Hello, seeking world!")
test_file:flush()

test_file:close()
local io_t2 = io.type(test_file)
print("io.type of closed file:", io_t2)
assert(io_t2 == "closed file", "io.type closed failed")

-- test default input/output redirection
local out_redir = io.output(test_filename)
assert(out_redir ~= nil, "io.output failed")
io.write("Duo Redirection Works!")
io.flush()
io.output(nil) -- reset
out_redir:close()

local test_file_read = io.open(test_filename, "r")
local seek_pos = test_file_read:seek("set", 4)
print("File seek set to 4 pos:", seek_pos)
assert(seek_pos == 4, "seek failed")

local read_content = test_file_read:read()
print("Read after seek content:", read_content)
assert(read_content == "Redirection Works!", "file seek / read failed")
test_file_read:close()

-- Clean up
os.remove(test_filename)

-- popen / lines
local pipe = io.popen("echo 'Duo pipe output'")
assert(pipe ~= nil, "io.popen failed")
local pipe_out = pipe:read()
print("Pipe output:", pipe_out)
assert(pipe_out == "Duo pipe output", "pipe read failed")
pipe:close()

-- local lin_res = io.lines("somefile.lua")
-- assert(lin_res == nil, "io.lines failed")
local lines_file = "duo_io_lines_test.txt"
local lw = io.open(lines_file, "w")
lw:write("line1\nline2\n")
lw:close()
local iter = io.lines(lines_file)
assert(iter() == "line1", "io.lines first failed")
assert(iter() == "line2", "io.lines second failed")
assert(iter() == nil, "io.lines third failed")
os.remove(lines_file)
print("io.lines: ok")

print("\nAll remaining global and module standard library functions compiled and executed successfully!")

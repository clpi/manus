file=./examples/stdlib_full_test.lua
hyperfine "nelua-lua $file" "duo run $file" "luajit $file" "lua $file"

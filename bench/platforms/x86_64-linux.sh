# Platform: x86_64-linux. STATUS: not yet supported.
# Backend needed: ELF object emission for x86_64.
# run.sh aborts on this host until the backend lands. To enable:
#   1. implement the backend in lib/compiler/,
#   2. add the link/assemble commands here,
#   3. remove the abort in run.sh for this uname pair.

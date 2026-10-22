savedcmd_bitbang.mod := printf '%s\n'   bitbang.o | awk '!x[$$0]++ { print("./"$$0) }' > bitbang.mod

savedcmd_sfio.mod := printf '%s\n'   sfio.o | awk '!x[$$0]++ { print("./"$$0) }' > sfio.mod

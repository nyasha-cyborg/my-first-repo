savedcmd_padsample.mod := printf '%s\n'   padsample.o | awk '!x[$$0]++ { print("./"$$0) }' > padsample.mod

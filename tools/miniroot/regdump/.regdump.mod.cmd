savedcmd_regdump.mod := printf '%s\n'   regdump.o | awk '!x[$$0]++ { print("./"$$0) }' > regdump.mod

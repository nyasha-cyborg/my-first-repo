savedcmd_sfio.ko := ld.lld -r -EL  -maarch64elf -z norelro -z noexecstack --build-id=sha1  -T /home/nyasha/code/linux-flounder-out/scripts/module.lds -o sfio.ko sfio.o sfio.mod.o .module-common.o

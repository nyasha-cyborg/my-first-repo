savedcmd_sfio.mod.o := clang -Wp,-MMD,./.sfio.mod.o.d -nostdinc -I/home/nyasha/code/linux-flounder/arch/arm64/include -I/home/nyasha/code/linux-flounder-out/arch/arm64/include/generated -I/home/nyasha/code/linux-flounder/include -I/home/nyasha/code/linux-flounder-out/include -I/home/nyasha/code/linux-flounder/arch/arm64/include/uapi -I/home/nyasha/code/linux-flounder-out/arch/arm64/include/generated/uapi -I/home/nyasha/code/linux-flounder/include/uapi -I/home/nyasha/code/linux-flounder-out/include/generated/uapi -include /home/nyasha/code/linux-flounder/include/linux/compiler-version.h -include /home/nyasha/code/linux-flounder/include/linux/kconfig.h -include /home/nyasha/code/linux-flounder/include/linux/compiler_types.h -D__KERNEL__ --target=aarch64-linux-gnu -fintegrated-as -Werror=unknown-warning-option -Werror=ignored-optimization-argument -Werror=option-ignored -Werror=unused-command-line-argument -mlittle-endian -DKASAN_SHADOW_SCALE_SHIFT= -std=gnu11 -fshort-wchar -funsigned-char -fno-common -fno-PIE -fno-strict-aliasing -mgeneral-regs-only -DCONFIG_CC_HAS_K_CONSTRAINT=1 -Wno-psabi -fno-asynchronous-unwind-tables -fno-unwind-tables -mbranch-protection=none -Wa,-march=armv8.5-a -DARM64_ASM_ARCH='"armv8.5-a"' -DKASAN_SHADOW_SCALE_SHIFT= -fno-delete-null-pointer-checks -O2 -fstack-protector-strong -fno-omit-frame-pointer -fno-optimize-sibling-calls -fno-stack-clash-protection -falign-functions=4 -fstrict-flex-arrays=3 -fms-extensions -fno-strict-overflow -fno-stack-check -fno-builtin-wcslen -Wall -Wextra -Wundef -Werror=implicit-function-declaration -Werror=implicit-int -Werror=return-type -Werror=strict-prototypes -Wno-format-security -Wno-trigraphs -Wno-frame-address -Wno-address-of-packed-member -Wmissing-declarations -Wmissing-prototypes -Wframe-larger-than=2048 -Wno-gnu -Wno-microsoft-anon-tag -Wno-format-overflow-non-kprintf -Wno-format-truncation-non-kprintf -Wno-default-const-init-unsafe -Wno-pointer-sign -Wcast-function-type -Wno-unterminated-string-initialization -Wimplicit-fallthrough -Werror=date-time -Werror=incompatible-pointer-types -Wenum-conversion -Wunused -Wno-unused-but-set-variable -Wno-unused-const-variable -Wno-format-overflow -Wno-override-init -Wno-pointer-to-enum-cast -Wno-tautological-constant-out-of-range-compare -Wno-unaligned-access -Wno-enum-compare-conditional -Wno-missing-field-initializers -Wno-type-limits -Wno-shift-negative-value -Wno-enum-enum-conversion -Wno-sign-compare -Wno-unused-parameter -g -fno-var-tracking -mstack-protector-guard=sysreg -mstack-protector-guard-reg=sp_el0 -mstack-protector-guard-offset=1312  -DMODULE  -DKBUILD_BASENAME='"sfio.mod"' -DKBUILD_MODNAME='"sfio"' -D__KBUILD_MODNAME=sfio -c -o sfio.mod.o sfio.mod.c  

source_sfio.mod.o := sfio.mod.c

deps_sfio.mod.o := \
  /home/nyasha/code/linux-flounder/include/linux/compiler-version.h \
    $(wildcard include/config/CC_VERSION_TEXT) \
  /home/nyasha/code/linux-flounder/include/linux/kconfig.h \
    $(wildcard include/config/CPU_BIG_ENDIAN) \
    $(wildcard include/config/BOOGER) \
    $(wildcard include/config/FOO) \
  /home/nyasha/code/linux-flounder/include/linux/compiler_types.h \
    $(wildcard include/config/DEBUG_INFO_BTF) \
    $(wildcard include/config/PAHOLE_HAS_BTF_TAG) \
    $(wildcard include/config/FUNCTION_ALIGNMENT) \
    $(wildcard include/config/CC_HAS_SANE_FUNCTION_ALIGNMENT) \
    $(wildcard include/config/X86_64) \
    $(wildcard include/config/ARM64) \
    $(wildcard include/config/LD_DEAD_CODE_DATA_ELIMINATION) \
    $(wildcard include/config/LTO_CLANG) \
    $(wildcard include/config/HAVE_ARCH_COMPILER_H) \
    $(wildcard include/config/CC_HAS_ASSUME) \
    $(wildcard include/config/CC_HAS_COUNTED_BY) \
    $(wildcard include/config/CC_HAS_MULTIDIMENSIONAL_NONSTRING) \
    $(wildcard include/config/UBSAN_INTEGER_WRAP) \
    $(wildcard include/config/CFI) \
    $(wildcard include/config/ARCH_USES_CFI_GENERIC_LLVM_PASS) \
    $(wildcard include/config/CC_HAS_ASM_INLINE) \
  /home/nyasha/code/linux-flounder/include/linux/compiler_attributes.h \
  /home/nyasha/code/linux-flounder/include/linux/compiler-clang.h \
    $(wildcard include/config/ARCH_USE_BUILTIN_BSWAP) \
    $(wildcard include/config/CC_HAS_TYPEOF_UNQUAL) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/compiler.h \
    $(wildcard include/config/ARM64_PTR_AUTH_KERNEL) \
    $(wildcard include/config/ARM64_PTR_AUTH) \
    $(wildcard include/config/BUILTIN_RETURN_ADDRESS_STRIPS_PAC) \
  /home/nyasha/code/linux-flounder/include/linux/module.h \
    $(wildcard include/config/MODULES) \
    $(wildcard include/config/SYSFS) \
    $(wildcard include/config/MODULES_TREE_LOOKUP) \
    $(wildcard include/config/LIVEPATCH) \
    $(wildcard include/config/STACKTRACE_BUILD_ID) \
    $(wildcard include/config/ARCH_USES_CFI_TRAPS) \
    $(wildcard include/config/MODULE_SIG) \
    $(wildcard include/config/GENERIC_BUG) \
    $(wildcard include/config/KALLSYMS) \
    $(wildcard include/config/SMP) \
    $(wildcard include/config/TRACEPOINTS) \
    $(wildcard include/config/TREE_SRCU) \
    $(wildcard include/config/BPF_EVENTS) \
    $(wildcard include/config/DEBUG_INFO_BTF_MODULES) \
    $(wildcard include/config/JUMP_LABEL) \
    $(wildcard include/config/TRACING) \
    $(wildcard include/config/EVENT_TRACING) \
    $(wildcard include/config/DYNAMIC_FTRACE) \
    $(wildcard include/config/KPROBES) \
    $(wildcard include/config/HAVE_STATIC_CALL_INLINE) \
    $(wildcard include/config/KUNIT) \
    $(wildcard include/config/PRINTK_INDEX) \
    $(wildcard include/config/MODULE_UNLOAD) \
    $(wildcard include/config/CONSTRUCTORS) \
    $(wildcard include/config/FUNCTION_ERROR_INJECTION) \
    $(wildcard include/config/DYNAMIC_DEBUG_CORE) \
    $(wildcard include/config/MITIGATION_RETPOLINE) \
  /home/nyasha/code/linux-flounder/include/linux/list.h \
    $(wildcard include/config/LIST_HARDENED) \
    $(wildcard include/config/DEBUG_LIST) \
  /home/nyasha/code/linux-flounder/include/linux/container_of.h \
  /home/nyasha/code/linux-flounder/include/linux/build_bug.h \
  /home/nyasha/code/linux-flounder/include/linux/compiler.h \
    $(wildcard include/config/TRACE_BRANCH_PROFILING) \
    $(wildcard include/config/PROFILE_ALL_BRANCHES) \
    $(wildcard include/config/OBJTOOL) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/rwonce.h \
    $(wildcard include/config/LTO) \
  /home/nyasha/code/linux-flounder/include/asm-generic/rwonce.h \
  /home/nyasha/code/linux-flounder/include/linux/kasan-checks.h \
    $(wildcard include/config/KASAN_GENERIC) \
    $(wildcard include/config/KASAN_SW_TAGS) \
  /home/nyasha/code/linux-flounder/include/linux/types.h \
    $(wildcard include/config/HAVE_UID16) \
    $(wildcard include/config/UID16) \
    $(wildcard include/config/ARCH_DMA_ADDR_T_64BIT) \
    $(wildcard include/config/PHYS_ADDR_T_64BIT) \
    $(wildcard include/config/64BIT) \
    $(wildcard include/config/ARCH_32BIT_USTAT_F_TINODE) \
  /home/nyasha/code/linux-flounder/include/uapi/linux/types.h \
  /home/nyasha/code/linux-flounder-out/arch/arm64/include/generated/uapi/asm/types.h \
  /home/nyasha/code/linux-flounder/include/uapi/asm-generic/types.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/int-ll64.h \
  /home/nyasha/code/linux-flounder/include/uapi/asm-generic/int-ll64.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/uapi/asm/bitsperlong.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/bitsperlong.h \
  /home/nyasha/code/linux-flounder/include/uapi/asm-generic/bitsperlong.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/posix_types.h \
  /home/nyasha/code/linux-flounder/include/linux/stddef.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/stddef.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/uapi/asm/posix_types.h \
  /home/nyasha/code/linux-flounder/include/uapi/asm-generic/posix_types.h \
  /home/nyasha/code/linux-flounder/include/linux/kcsan-checks.h \
    $(wildcard include/config/KCSAN) \
    $(wildcard include/config/KCSAN_WEAK_MEMORY) \
    $(wildcard include/config/KCSAN_IGNORE_ATOMICS) \
  /home/nyasha/code/linux-flounder/include/linux/poison.h \
    $(wildcard include/config/ILLEGAL_POINTER_VALUE) \
  /home/nyasha/code/linux-flounder/include/linux/const.h \
  /home/nyasha/code/linux-flounder/include/vdso/const.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/const.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/barrier.h \
    $(wildcard include/config/ARM64_PSEUDO_NMI) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/alternative-macros.h \
  /home/nyasha/code/linux-flounder/include/vdso/bits.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/cpucaps.h \
    $(wildcard include/config/ARM64_PAN) \
    $(wildcard include/config/ARM64_EPAN) \
    $(wildcard include/config/ARM64_SVE) \
    $(wildcard include/config/ARM64_SME) \
    $(wildcard include/config/ARM64_CNP) \
    $(wildcard include/config/ARM64_MTE) \
    $(wildcard include/config/ARM64_BTI) \
    $(wildcard include/config/ARM64_TLB_RANGE) \
    $(wildcard include/config/ARM64_POE) \
    $(wildcard include/config/ARM64_GCS) \
    $(wildcard include/config/ARM64_HAFT) \
    $(wildcard include/config/UNMAP_KERNEL_AT_EL0) \
    $(wildcard include/config/ARM64_ERRATUM_843419) \
    $(wildcard include/config/ARM64_ERRATUM_1742098) \
    $(wildcard include/config/ARM64_ERRATUM_2645198) \
    $(wildcard include/config/ARM64_ERRATUM_2658417) \
    $(wildcard include/config/CAVIUM_ERRATUM_23154) \
    $(wildcard include/config/NVIDIA_CARMEL_CNP_ERRATUM) \
    $(wildcard include/config/ARM64_WORKAROUND_REPEAT_TLBI) \
    $(wildcard include/config/ARM64_ERRATUM_3194386) \
    $(wildcard include/config/HW_PERF_EVENTS) \
  /home/nyasha/code/linux-flounder-out/arch/arm64/include/generated/asm/cpucap-defs.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/insn-def.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/brk-imm.h \
  /home/nyasha/code/linux-flounder/include/linux/stringify.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/barrier.h \
  /home/nyasha/code/linux-flounder/include/linux/stat.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/stat.h \
    $(wildcard include/config/COMPAT) \
  /home/nyasha/code/linux-flounder-out/arch/arm64/include/generated/uapi/asm/stat.h \
  /home/nyasha/code/linux-flounder/include/uapi/asm-generic/stat.h \
  /home/nyasha/code/linux-flounder/include/linux/time.h \
    $(wildcard include/config/POSIX_TIMERS) \
  /home/nyasha/code/linux-flounder/include/linux/cache.h \
    $(wildcard include/config/ARCH_HAS_CACHE_LINE_SIZE) \
  /home/nyasha/code/linux-flounder/include/uapi/linux/kernel.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/sysinfo.h \
  /home/nyasha/code/linux-flounder/include/vdso/cache.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/cache.h \
    $(wildcard include/config/KASAN_HW_TAGS) \
  /home/nyasha/code/linux-flounder/include/linux/bitops.h \
  /home/nyasha/code/linux-flounder/include/linux/bits.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/bits.h \
  /home/nyasha/code/linux-flounder/include/linux/overflow.h \
  /home/nyasha/code/linux-flounder/include/linux/limits.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/limits.h \
  /home/nyasha/code/linux-flounder/include/vdso/limits.h \
  /home/nyasha/code/linux-flounder/include/linux/typecheck.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/bitops/generic-non-atomic.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/bitops.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/bitops/builtin-__ffs.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/bitops/builtin-ffs.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/bitops/builtin-__fls.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/bitops/builtin-fls.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/bitops/ffz.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/bitops/fls64.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/bitops/sched.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/bitops/hweight.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/bitops/arch_hweight.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/bitops/const_hweight.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/bitops/atomic.h \
  /home/nyasha/code/linux-flounder/include/linux/atomic.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/atomic.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/cmpxchg.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/lse.h \
    $(wildcard include/config/ARM64_LSE_ATOMICS) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/atomic_ll_sc.h \
    $(wildcard include/config/CC_HAS_K_CONSTRAINT) \
  /home/nyasha/code/linux-flounder/include/linux/atomic/atomic-arch-fallback.h \
    $(wildcard include/config/GENERIC_ATOMIC64) \
  /home/nyasha/code/linux-flounder/include/linux/atomic/atomic-long.h \
  /home/nyasha/code/linux-flounder/include/linux/atomic/atomic-instrumented.h \
  /home/nyasha/code/linux-flounder/include/linux/instrumented.h \
  /home/nyasha/code/linux-flounder/include/linux/kmsan-checks.h \
    $(wildcard include/config/KMSAN) \
  /home/nyasha/code/linux-flounder/include/asm-generic/bitops/instrumented-atomic.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/bitops/lock.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/bitops/instrumented-lock.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/bitops/non-atomic.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/bitops/non-instrumented-non-atomic.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/bitops/le.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/uapi/asm/byteorder.h \
  /home/nyasha/code/linux-flounder/include/linux/byteorder/little_endian.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/byteorder/little_endian.h \
  /home/nyasha/code/linux-flounder/include/linux/swab.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/swab.h \
  /home/nyasha/code/linux-flounder-out/arch/arm64/include/generated/uapi/asm/swab.h \
  /home/nyasha/code/linux-flounder/include/uapi/asm-generic/swab.h \
  /home/nyasha/code/linux-flounder/include/linux/byteorder/generic.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/bitops/ext2-atomic-setbit.h \
  /home/nyasha/code/linux-flounder/include/linux/kasan-enabled.h \
    $(wildcard include/config/ARCH_DEFER_KASAN) \
    $(wildcard include/config/KASAN) \
  /home/nyasha/code/linux-flounder/include/linux/static_key.h \
  /home/nyasha/code/linux-flounder/include/linux/jump_label.h \
    $(wildcard include/config/HAVE_ARCH_JUMP_LABEL_RELATIVE) \
  /home/nyasha/code/linux-flounder/include/linux/cleanup.h \
  /home/nyasha/code/linux-flounder/include/linux/err.h \
  /home/nyasha/code/linux-flounder-out/arch/arm64/include/generated/uapi/asm/errno.h \
  /home/nyasha/code/linux-flounder/include/uapi/asm-generic/errno.h \
  /home/nyasha/code/linux-flounder/include/uapi/asm-generic/errno-base.h \
  /home/nyasha/code/linux-flounder/include/linux/args.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/jump_label.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/insn.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/cputype.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/sysreg.h \
    $(wildcard include/config/BROKEN_GAS_INST) \
    $(wildcard include/config/ARM64_PA_BITS_52) \
    $(wildcard include/config/ARM64_4K_PAGES) \
    $(wildcard include/config/ARM64_16K_PAGES) \
    $(wildcard include/config/ARM64_64K_PAGES) \
    $(wildcard include/config/AMPERE_ERRATUM_AC04_CPU_23) \
  /home/nyasha/code/linux-flounder/include/linux/kasan-tags.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/gpr-num.h \
  /home/nyasha/code/linux-flounder-out/arch/arm64/include/generated/asm/sysreg-defs.h \
  /home/nyasha/code/linux-flounder/include/linux/bitfield.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/alternative.h \
  /home/nyasha/code/linux-flounder/include/linux/init.h \
    $(wildcard include/config/MEMORY_HOTPLUG) \
    $(wildcard include/config/HAVE_ARCH_PREL32_RELOCATIONS) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/mte-def.h \
  /home/nyasha/code/linux-flounder/include/linux/math64.h \
    $(wildcard include/config/ARCH_SUPPORTS_INT128) \
  /home/nyasha/code/linux-flounder/include/linux/math.h \
  /home/nyasha/code/linux-flounder-out/arch/arm64/include/generated/asm/div64.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/div64.h \
    $(wildcard include/config/CC_OPTIMIZE_FOR_PERFORMANCE) \
  /home/nyasha/code/linux-flounder/include/vdso/math64.h \
  /home/nyasha/code/linux-flounder/include/linux/time64.h \
  /home/nyasha/code/linux-flounder/include/vdso/time64.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/time.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/time_types.h \
  /home/nyasha/code/linux-flounder/include/linux/time32.h \
  /home/nyasha/code/linux-flounder/include/linux/timex.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/timex.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/param.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/uapi/asm/param.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/param.h \
    $(wildcard include/config/HZ) \
  /home/nyasha/code/linux-flounder/include/uapi/asm-generic/param.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/timex.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/arch_timer.h \
    $(wildcard include/config/ARM_ARCH_TIMER_OOL_WORKAROUND) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/hwcap.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/uapi/asm/hwcap.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/cpufeature.h \
    $(wildcard include/config/ARM64_SW_TTBR0_PAN) \
    $(wildcard include/config/ARM64_DEBUG_PRIORITY_MASKING) \
    $(wildcard include/config/ARM64_BTI_KERNEL) \
    $(wildcard include/config/ARM64_PA_BITS) \
    $(wildcard include/config/ARM64_HW_AFDBM) \
    $(wildcard include/config/ARM64_AMU_EXTN) \
    $(wildcard include/config/ARM64_LPA2) \
  /home/nyasha/code/linux-flounder/include/linux/bug.h \
    $(wildcard include/config/PRINTK) \
    $(wildcard include/config/BUG_ON_DATA_CORRUPTION) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/bug.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/asm-bug.h \
    $(wildcard include/config/DEBUG_BUGVERBOSE) \
  /home/nyasha/code/linux-flounder/include/asm-generic/bug.h \
    $(wildcard include/config/DEBUG_BUGVERBOSE_DETAILED) \
    $(wildcard include/config/BUG) \
    $(wildcard include/config/GENERIC_BUG_RELATIVE_POINTERS) \
  /home/nyasha/code/linux-flounder/include/linux/instrumentation.h \
    $(wildcard include/config/NOINSTR_VALIDATION) \
  /home/nyasha/code/linux-flounder/include/linux/once_lite.h \
  /home/nyasha/code/linux-flounder/include/linux/panic.h \
    $(wildcard include/config/PANIC_TIMEOUT) \
  /home/nyasha/code/linux-flounder/include/linux/stdarg.h \
  /home/nyasha/code/linux-flounder/include/linux/printk.h \
    $(wildcard include/config/MESSAGE_LOGLEVEL_DEFAULT) \
    $(wildcard include/config/CONSOLE_LOGLEVEL_DEFAULT) \
    $(wildcard include/config/CONSOLE_LOGLEVEL_QUIET) \
    $(wildcard include/config/EARLY_PRINTK) \
    $(wildcard include/config/DYNAMIC_DEBUG) \
  /home/nyasha/code/linux-flounder/include/linux/kern_levels.h \
  /home/nyasha/code/linux-flounder/include/linux/linkage.h \
    $(wildcard include/config/ARCH_USE_SYM_ANNOTATIONS) \
  /home/nyasha/code/linux-flounder/include/linux/export.h \
    $(wildcard include/config/MODVERSIONS) \
    $(wildcard include/config/GENDWARFKSYMS) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/linkage.h \
  /home/nyasha/code/linux-flounder/include/linux/ratelimit_types.h \
  /home/nyasha/code/linux-flounder/include/linux/spinlock_types_raw.h \
    $(wildcard include/config/DEBUG_SPINLOCK) \
    $(wildcard include/config/DEBUG_LOCK_ALLOC) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/spinlock_types.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/qspinlock_types.h \
    $(wildcard include/config/NR_CPUS) \
  /home/nyasha/code/linux-flounder/include/asm-generic/qrwlock_types.h \
  /home/nyasha/code/linux-flounder/include/linux/lockdep_types.h \
    $(wildcard include/config/PROVE_RAW_LOCK_NESTING) \
    $(wildcard include/config/LOCKDEP) \
    $(wildcard include/config/LOCK_STAT) \
  /home/nyasha/code/linux-flounder/include/linux/kernel.h \
    $(wildcard include/config/PREEMPT_VOLUNTARY_BUILD) \
    $(wildcard include/config/PREEMPT_DYNAMIC) \
    $(wildcard include/config/HAVE_PREEMPT_DYNAMIC_CALL) \
    $(wildcard include/config/HAVE_PREEMPT_DYNAMIC_KEY) \
    $(wildcard include/config/PREEMPT_) \
    $(wildcard include/config/DEBUG_ATOMIC_SLEEP) \
    $(wildcard include/config/MMU) \
    $(wildcard include/config/PROVE_LOCKING) \
  /home/nyasha/code/linux-flounder/include/linux/align.h \
  /home/nyasha/code/linux-flounder/include/vdso/align.h \
  /home/nyasha/code/linux-flounder/include/linux/array_size.h \
  /home/nyasha/code/linux-flounder/include/linux/hex.h \
  /home/nyasha/code/linux-flounder/include/linux/kstrtox.h \
  /home/nyasha/code/linux-flounder/include/linux/log2.h \
    $(wildcard include/config/ARCH_HAS_ILOG2_U32) \
    $(wildcard include/config/ARCH_HAS_ILOG2_U64) \
  /home/nyasha/code/linux-flounder/include/linux/minmax.h \
  /home/nyasha/code/linux-flounder/include/linux/sprintf.h \
  /home/nyasha/code/linux-flounder/include/linux/static_call_types.h \
    $(wildcard include/config/HAVE_STATIC_CALL) \
  /home/nyasha/code/linux-flounder/include/linux/instruction_pointer.h \
  /home/nyasha/code/linux-flounder/include/linux/util_macros.h \
    $(wildcard include/config/FOO_SUSPEND) \
  /home/nyasha/code/linux-flounder/include/linux/wordpart.h \
  /home/nyasha/code/linux-flounder/include/linux/cpumask.h \
    $(wildcard include/config/FORCE_NR_CPUS) \
    $(wildcard include/config/HOTPLUG_CPU) \
    $(wildcard include/config/DEBUG_PER_CPU_MAPS) \
    $(wildcard include/config/CPUMASK_OFFSTACK) \
  /home/nyasha/code/linux-flounder/include/linux/bitmap.h \
  /home/nyasha/code/linux-flounder/include/linux/errno.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/errno.h \
  /home/nyasha/code/linux-flounder/include/linux/find.h \
  /home/nyasha/code/linux-flounder/include/linux/string.h \
    $(wildcard include/config/BINARY_PRINTF) \
    $(wildcard include/config/FORTIFY_SOURCE) \
  /home/nyasha/code/linux-flounder/include/uapi/linux/string.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/string.h \
    $(wildcard include/config/ARCH_HAS_UACCESS_FLUSHCACHE) \
  /home/nyasha/code/linux-flounder/include/linux/bitmap-str.h \
  /home/nyasha/code/linux-flounder/include/linux/cpumask_types.h \
  /home/nyasha/code/linux-flounder/include/linux/threads.h \
    $(wildcard include/config/BASE_SMALL) \
  /home/nyasha/code/linux-flounder/include/linux/gfp_types.h \
  /home/nyasha/code/linux-flounder/include/linux/numa.h \
    $(wildcard include/config/NUMA_KEEP_MEMINFO) \
    $(wildcard include/config/NUMA) \
    $(wildcard include/config/HAVE_ARCH_NODE_DEV_GROUP) \
  /home/nyasha/code/linux-flounder/include/linux/nodemask.h \
    $(wildcard include/config/HIGHMEM) \
  /home/nyasha/code/linux-flounder/include/linux/nodemask_types.h \
    $(wildcard include/config/NODES_SHIFT) \
  /home/nyasha/code/linux-flounder/include/linux/random.h \
    $(wildcard include/config/VMGENID) \
  /home/nyasha/code/linux-flounder/include/uapi/linux/random.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/ioctl.h \
  /home/nyasha/code/linux-flounder-out/arch/arm64/include/generated/uapi/asm/ioctl.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/ioctl.h \
  /home/nyasha/code/linux-flounder/include/uapi/asm-generic/ioctl.h \
  /home/nyasha/code/linux-flounder/include/linux/irqnr.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/irqnr.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/sparsemem.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/pgtable-prot.h \
    $(wildcard include/config/HAVE_ARCH_USERFAULTFD_WP) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/memory.h \
    $(wildcard include/config/ARM64_VA_BITS) \
    $(wildcard include/config/KASAN_SHADOW_OFFSET) \
    $(wildcard include/config/RANDOMIZE_BASE) \
    $(wildcard include/config/DEBUG_VIRTUAL) \
    $(wildcard include/config/EFI) \
    $(wildcard include/config/ARM_GIC_V3_ITS) \
  /home/nyasha/code/linux-flounder/include/linux/sizes.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/page-def.h \
  /home/nyasha/code/linux-flounder/include/vdso/page.h \
    $(wildcard include/config/PAGE_SHIFT) \
  /home/nyasha/code/linux-flounder/include/linux/mmdebug.h \
    $(wildcard include/config/DEBUG_VM) \
    $(wildcard include/config/DEBUG_VM_IRQSOFF) \
    $(wildcard include/config/DEBUG_VM_PGFLAGS) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/boot.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/sections.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/sections.h \
    $(wildcard include/config/HAVE_FUNCTION_DESCRIPTORS) \
  /home/nyasha/code/linux-flounder/include/asm-generic/memory_model.h \
    $(wildcard include/config/FLATMEM) \
    $(wildcard include/config/SPARSEMEM_VMEMMAP) \
    $(wildcard include/config/SPARSEMEM) \
  /home/nyasha/code/linux-flounder/include/linux/pfn.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/pgtable-hwdef.h \
    $(wildcard include/config/PGTABLE_LEVELS) \
    $(wildcard include/config/ARM64_CONT_PTE_SHIFT) \
    $(wildcard include/config/ARM64_CONT_PMD_SHIFT) \
    $(wildcard include/config/ARM64_VA_BITS_52) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/pgtable-types.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/pgtable-nop4d.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/rsi.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/rsi_cmds.h \
  /home/nyasha/code/linux-flounder/include/linux/arm-smccc.h \
    $(wildcard include/config/HAVE_ARM_SMCCC) \
    $(wildcard include/config/ARM) \
  /home/nyasha/code/linux-flounder/include/linux/uuid.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/rsi_smc.h \
  /home/nyasha/code/linux-flounder/include/linux/percpu.h \
    $(wildcard include/config/RANDOM_KMALLOC_CACHES) \
    $(wildcard include/config/PAGE_SIZE_4KB) \
    $(wildcard include/config/NEED_PER_CPU_PAGE_FIRST_CHUNK) \
    $(wildcard include/config/HAVE_SETUP_PER_CPU_AREA) \
  /home/nyasha/code/linux-flounder/include/linux/alloc_tag.h \
    $(wildcard include/config/MEM_ALLOC_PROFILING_DEBUG) \
    $(wildcard include/config/MEM_ALLOC_PROFILING) \
    $(wildcard include/config/ARCH_MODULE_NEEDS_WEAK_PER_CPU) \
    $(wildcard include/config/MEM_ALLOC_PROFILING_ENABLED_BY_DEFAULT) \
  /home/nyasha/code/linux-flounder/include/linux/codetag.h \
    $(wildcard include/config/CODE_TAGGING) \
  /home/nyasha/code/linux-flounder/include/linux/preempt.h \
    $(wildcard include/config/PREEMPT_RT) \
    $(wildcard include/config/PREEMPT_COUNT) \
    $(wildcard include/config/DEBUG_PREEMPT) \
    $(wildcard include/config/TRACE_PREEMPT_TOGGLE) \
    $(wildcard include/config/PREEMPTION) \
    $(wildcard include/config/PREEMPT_NOTIFIERS) \
    $(wildcard include/config/PREEMPT_NONE) \
    $(wildcard include/config/PREEMPT_VOLUNTARY) \
    $(wildcard include/config/PREEMPT) \
    $(wildcard include/config/PREEMPT_LAZY) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/preempt.h \
  /home/nyasha/code/linux-flounder/include/linux/thread_info.h \
    $(wildcard include/config/THREAD_INFO_IN_TASK) \
    $(wildcard include/config/GENERIC_ENTRY) \
    $(wildcard include/config/ARCH_HAS_PREEMPT_LAZY) \
    $(wildcard include/config/HAVE_ARCH_WITHIN_STACK_FRAMES) \
    $(wildcard include/config/SH) \
  /home/nyasha/code/linux-flounder/include/linux/restart_block.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/current.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/thread_info.h \
    $(wildcard include/config/SHADOW_CALL_STACK) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/stack_pointer.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/percpu.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/percpu.h \
  /home/nyasha/code/linux-flounder/include/linux/percpu-defs.h \
    $(wildcard include/config/DEBUG_FORCE_WEAK_PER_CPU) \
    $(wildcard include/config/AMD_MEM_ENCRYPT) \
  /home/nyasha/code/linux-flounder/include/linux/smp.h \
    $(wildcard include/config/UP_LATE_INIT) \
    $(wildcard include/config/CSD_LOCK_WAIT_DEBUG) \
  /home/nyasha/code/linux-flounder/include/linux/smp_types.h \
  /home/nyasha/code/linux-flounder/include/linux/llist.h \
    $(wildcard include/config/ARCH_HAVE_NMI_SAFE_CMPXCHG) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/smp.h \
    $(wildcard include/config/ARM64_ACPI_PARKING_PROTOCOL) \
  /home/nyasha/code/linux-flounder/include/linux/irqflags.h \
    $(wildcard include/config/TRACE_IRQFLAGS) \
    $(wildcard include/config/IRQSOFF_TRACER) \
    $(wildcard include/config/PREEMPT_TRACER) \
    $(wildcard include/config/DEBUG_IRQFLAGS) \
    $(wildcard include/config/TRACE_IRQFLAGS_SUPPORT) \
  /home/nyasha/code/linux-flounder/include/linux/irqflags_types.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/irqflags.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/ptrace.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/uapi/asm/ptrace.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/uapi/asm/sve_context.h \
  /home/nyasha/code/linux-flounder/include/linux/irqchip/arm-gic-v3-prio.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/stacktrace/frame.h \
  /home/nyasha/code/linux-flounder/include/linux/sched.h \
    $(wildcard include/config/VIRT_CPU_ACCOUNTING_NATIVE) \
    $(wildcard include/config/SCHED_INFO) \
    $(wildcard include/config/SCHEDSTATS) \
    $(wildcard include/config/SCHED_CORE) \
    $(wildcard include/config/FAIR_GROUP_SCHED) \
    $(wildcard include/config/RT_GROUP_SCHED) \
    $(wildcard include/config/RT_MUTEXES) \
    $(wildcard include/config/UCLAMP_TASK) \
    $(wildcard include/config/UCLAMP_BUCKETS_COUNT) \
    $(wildcard include/config/KMAP_LOCAL) \
    $(wildcard include/config/SCHED_CLASS_EXT) \
    $(wildcard include/config/CGROUP_SCHED) \
    $(wildcard include/config/CFS_BANDWIDTH) \
    $(wildcard include/config/BLK_DEV_IO_TRACE) \
    $(wildcard include/config/PREEMPT_RCU) \
    $(wildcard include/config/TASKS_RCU) \
    $(wildcard include/config/TASKS_TRACE_RCU) \
    $(wildcard include/config/MEMCG_V1) \
    $(wildcard include/config/LRU_GEN) \
    $(wildcard include/config/COMPAT_BRK) \
    $(wildcard include/config/CGROUPS) \
    $(wildcard include/config/BLK_CGROUP) \
    $(wildcard include/config/PSI) \
    $(wildcard include/config/PAGE_OWNER) \
    $(wildcard include/config/EVENTFD) \
    $(wildcard include/config/ARCH_HAS_CPU_PASID) \
    $(wildcard include/config/X86_BUS_LOCK_DETECT) \
    $(wildcard include/config/TASK_DELAY_ACCT) \
    $(wildcard include/config/STACKPROTECTOR) \
    $(wildcard include/config/ARCH_HAS_SCALED_CPUTIME) \
    $(wildcard include/config/VIRT_CPU_ACCOUNTING_GEN) \
    $(wildcard include/config/NO_HZ_FULL) \
    $(wildcard include/config/POSIX_CPUTIMERS) \
    $(wildcard include/config/POSIX_CPU_TIMERS_TASK_WORK) \
    $(wildcard include/config/KEYS) \
    $(wildcard include/config/SYSVIPC) \
    $(wildcard include/config/DETECT_HUNG_TASK) \
    $(wildcard include/config/IO_URING) \
    $(wildcard include/config/AUDIT) \
    $(wildcard include/config/AUDITSYSCALL) \
    $(wildcard include/config/DETECT_HUNG_TASK_BLOCKER) \
    $(wildcard include/config/UBSAN) \
    $(wildcard include/config/UBSAN_TRAP) \
    $(wildcard include/config/COMPACTION) \
    $(wildcard include/config/TASK_XACCT) \
    $(wildcard include/config/CPUSETS) \
    $(wildcard include/config/X86_CPU_RESCTRL) \
    $(wildcard include/config/FUTEX) \
    $(wildcard include/config/PERF_EVENTS) \
    $(wildcard include/config/NUMA_BALANCING) \
    $(wildcard include/config/FAULT_INJECTION) \
    $(wildcard include/config/LATENCYTOP) \
    $(wildcard include/config/FUNCTION_GRAPH_TRACER) \
    $(wildcard include/config/KCOV) \
    $(wildcard include/config/MEMCG) \
    $(wildcard include/config/UPROBES) \
    $(wildcard include/config/BCACHE) \
    $(wildcard include/config/VMAP_STACK) \
    $(wildcard include/config/SECURITY) \
    $(wildcard include/config/BPF_SYSCALL) \
    $(wildcard include/config/KSTACK_ERASE) \
    $(wildcard include/config/KSTACK_ERASE_METRICS) \
    $(wildcard include/config/X86_MCE) \
    $(wildcard include/config/KRETPROBES) \
    $(wildcard include/config/RETHOOK) \
    $(wildcard include/config/ARCH_HAS_PARANOID_L1D_FLUSH) \
    $(wildcard include/config/RV) \
    $(wildcard include/config/RV_PER_TASK_MONITORS) \
    $(wildcard include/config/USER_EVENTS) \
    $(wildcard include/config/UNWIND_USER) \
    $(wildcard include/config/SCHED_PROXY_EXEC) \
    $(wildcard include/config/SCHED_MM_CID) \
  /home/nyasha/code/linux-flounder/include/uapi/linux/sched.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/processor.h \
    $(wildcard include/config/KUSER_HELPERS) \
    $(wildcard include/config/ARM64_FORCE_52BIT) \
    $(wildcard include/config/HAVE_HW_BREAKPOINT) \
    $(wildcard include/config/ARM64_TAGGED_ADDR_ABI) \
  /home/nyasha/code/linux-flounder/include/vdso/processor.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/vdso/processor.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/hw_breakpoint.h \
    $(wildcard include/config/CPU_PM) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/virt.h \
    $(wildcard include/config/KVM) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/kasan.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/mte-kasan.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/pointer_auth.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/prctl.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/spectre.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/fpsimd.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/uapi/asm/sigcontext.h \
  /home/nyasha/code/linux-flounder/include/linux/pid_types.h \
  /home/nyasha/code/linux-flounder/include/linux/sem_types.h \
  /home/nyasha/code/linux-flounder/include/linux/shm.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/page.h \
  /home/nyasha/code/linux-flounder/include/linux/personality.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/personality.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/getorder.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/shmparam.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/shmparam.h \
  /home/nyasha/code/linux-flounder/include/linux/kmsan_types.h \
  /home/nyasha/code/linux-flounder/include/linux/mutex_types.h \
    $(wildcard include/config/MUTEX_SPIN_ON_OWNER) \
    $(wildcard include/config/DEBUG_MUTEXES) \
  /home/nyasha/code/linux-flounder/include/linux/osq_lock.h \
  /home/nyasha/code/linux-flounder/include/linux/spinlock_types.h \
  /home/nyasha/code/linux-flounder/include/linux/rwlock_types.h \
  /home/nyasha/code/linux-flounder/include/linux/plist_types.h \
  /home/nyasha/code/linux-flounder/include/linux/hrtimer_types.h \
  /home/nyasha/code/linux-flounder/include/linux/timerqueue_types.h \
  /home/nyasha/code/linux-flounder/include/linux/rbtree_types.h \
  /home/nyasha/code/linux-flounder/include/linux/timer_types.h \
  /home/nyasha/code/linux-flounder/include/linux/seccomp_types.h \
    $(wildcard include/config/SECCOMP) \
  /home/nyasha/code/linux-flounder/include/linux/refcount_types.h \
  /home/nyasha/code/linux-flounder/include/linux/resource.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/resource.h \
  /home/nyasha/code/linux-flounder-out/arch/arm64/include/generated/uapi/asm/resource.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/resource.h \
  /home/nyasha/code/linux-flounder/include/uapi/asm-generic/resource.h \
  /home/nyasha/code/linux-flounder/include/linux/latencytop.h \
  /home/nyasha/code/linux-flounder/include/linux/sched/prio.h \
  /home/nyasha/code/linux-flounder/include/linux/sched/types.h \
  /home/nyasha/code/linux-flounder/include/linux/signal_types.h \
    $(wildcard include/config/OLD_SIGACTION) \
  /home/nyasha/code/linux-flounder/include/uapi/linux/signal.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/signal.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/uapi/asm/signal.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/signal.h \
  /home/nyasha/code/linux-flounder/include/uapi/asm-generic/signal.h \
  /home/nyasha/code/linux-flounder/include/uapi/asm-generic/signal-defs.h \
  /home/nyasha/code/linux-flounder-out/arch/arm64/include/generated/uapi/asm/siginfo.h \
  /home/nyasha/code/linux-flounder/include/uapi/asm-generic/siginfo.h \
  /home/nyasha/code/linux-flounder/include/linux/spinlock.h \
  /home/nyasha/code/linux-flounder/include/linux/bottom_half.h \
  /home/nyasha/code/linux-flounder/include/linux/lockdep.h \
    $(wildcard include/config/DEBUG_LOCKING_API_SELFTESTS) \
  /home/nyasha/code/linux-flounder-out/arch/arm64/include/generated/asm/mmiowb.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/mmiowb.h \
    $(wildcard include/config/MMIOWB) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/spinlock.h \
  /home/nyasha/code/linux-flounder-out/arch/arm64/include/generated/asm/qspinlock.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/qspinlock.h \
  /home/nyasha/code/linux-flounder-out/arch/arm64/include/generated/asm/qrwlock.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/qrwlock.h \
  /home/nyasha/code/linux-flounder/include/linux/rwlock.h \
  /home/nyasha/code/linux-flounder/include/linux/spinlock_api_smp.h \
    $(wildcard include/config/INLINE_SPIN_LOCK) \
    $(wildcard include/config/INLINE_SPIN_LOCK_BH) \
    $(wildcard include/config/INLINE_SPIN_LOCK_IRQ) \
    $(wildcard include/config/INLINE_SPIN_LOCK_IRQSAVE) \
    $(wildcard include/config/INLINE_SPIN_TRYLOCK) \
    $(wildcard include/config/INLINE_SPIN_TRYLOCK_BH) \
    $(wildcard include/config/UNINLINE_SPIN_UNLOCK) \
    $(wildcard include/config/INLINE_SPIN_UNLOCK_BH) \
    $(wildcard include/config/INLINE_SPIN_UNLOCK_IRQ) \
    $(wildcard include/config/INLINE_SPIN_UNLOCK_IRQRESTORE) \
    $(wildcard include/config/GENERIC_LOCKBREAK) \
  /home/nyasha/code/linux-flounder/include/linux/rwlock_api_smp.h \
    $(wildcard include/config/INLINE_READ_LOCK) \
    $(wildcard include/config/INLINE_WRITE_LOCK) \
    $(wildcard include/config/INLINE_READ_LOCK_BH) \
    $(wildcard include/config/INLINE_WRITE_LOCK_BH) \
    $(wildcard include/config/INLINE_READ_LOCK_IRQ) \
    $(wildcard include/config/INLINE_WRITE_LOCK_IRQ) \
    $(wildcard include/config/INLINE_READ_LOCK_IRQSAVE) \
    $(wildcard include/config/INLINE_WRITE_LOCK_IRQSAVE) \
    $(wildcard include/config/INLINE_READ_TRYLOCK) \
    $(wildcard include/config/INLINE_WRITE_TRYLOCK) \
    $(wildcard include/config/INLINE_READ_UNLOCK) \
    $(wildcard include/config/INLINE_WRITE_UNLOCK) \
    $(wildcard include/config/INLINE_READ_UNLOCK_BH) \
    $(wildcard include/config/INLINE_WRITE_UNLOCK_BH) \
    $(wildcard include/config/INLINE_READ_UNLOCK_IRQ) \
    $(wildcard include/config/INLINE_WRITE_UNLOCK_IRQ) \
    $(wildcard include/config/INLINE_READ_UNLOCK_IRQRESTORE) \
    $(wildcard include/config/INLINE_WRITE_UNLOCK_IRQRESTORE) \
  /home/nyasha/code/linux-flounder/include/linux/syscall_user_dispatch_types.h \
  /home/nyasha/code/linux-flounder/include/linux/mm_types_task.h \
    $(wildcard include/config/ARCH_WANT_BATCHED_UNMAP_TLB_FLUSH) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/tlbbatch.h \
  /home/nyasha/code/linux-flounder/include/linux/netdevice_xmit.h \
    $(wildcard include/config/NET_ACT_MIRRED) \
    $(wildcard include/config/NET_EGRESS) \
    $(wildcard include/config/NF_DUP_NETDEV) \
  /home/nyasha/code/linux-flounder/include/linux/task_io_accounting.h \
    $(wildcard include/config/TASK_IO_ACCOUNTING) \
  /home/nyasha/code/linux-flounder/include/linux/posix-timers_types.h \
  /home/nyasha/code/linux-flounder/include/linux/rseq_types.h \
    $(wildcard include/config/RSEQ) \
  /home/nyasha/code/linux-flounder/include/linux/irq_work_types.h \
  /home/nyasha/code/linux-flounder/include/linux/workqueue_types.h \
  /home/nyasha/code/linux-flounder/include/linux/seqlock_types.h \
  /home/nyasha/code/linux-flounder/include/linux/kcsan.h \
  /home/nyasha/code/linux-flounder/include/linux/rv.h \
    $(wildcard include/config/RV_LTL_MONITOR) \
    $(wildcard include/config/RV_REACTORS) \
  /home/nyasha/code/linux-flounder/include/linux/uidgid_types.h \
  /home/nyasha/code/linux-flounder/include/linux/tracepoint-defs.h \
  /home/nyasha/code/linux-flounder/include/linux/unwind_deferred_types.h \
  /home/nyasha/code/linux-flounder-out/arch/arm64/include/generated/asm/kmap_size.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/kmap_size.h \
    $(wildcard include/config/DEBUG_KMAP_LOCAL) \
  /home/nyasha/code/linux-flounder-out/include/generated/rq-offsets.h \
  /home/nyasha/code/linux-flounder/include/linux/sched/ext.h \
    $(wildcard include/config/EXT_GROUP_SCHED) \
  /home/nyasha/code/linux-flounder/include/clocksource/arm_arch_timer.h \
    $(wildcard include/config/ARM_ARCH_TIMER) \
  /home/nyasha/code/linux-flounder/include/linux/timecounter.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/timex.h \
  /home/nyasha/code/linux-flounder/include/vdso/time32.h \
  /home/nyasha/code/linux-flounder/include/vdso/time.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/compat.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/compat.h \
    $(wildcard include/config/COMPAT_FOR_U64_ALIGNMENT) \
  /home/nyasha/code/linux-flounder/include/linux/sched/task_stack.h \
    $(wildcard include/config/STACK_GROWSUP) \
    $(wildcard include/config/DEBUG_STACK_USAGE) \
  /home/nyasha/code/linux-flounder/include/uapi/linux/magic.h \
  /home/nyasha/code/linux-flounder/include/linux/refcount.h \
  /home/nyasha/code/linux-flounder/include/linux/kasan.h \
    $(wildcard include/config/KASAN_STACK) \
    $(wildcard include/config/KASAN_VMALLOC) \
  /home/nyasha/code/linux-flounder/include/uapi/linux/stat.h \
  /home/nyasha/code/linux-flounder/include/linux/uidgid.h \
    $(wildcard include/config/MULTIUSER) \
    $(wildcard include/config/USER_NS) \
  /home/nyasha/code/linux-flounder/include/linux/highuid.h \
  /home/nyasha/code/linux-flounder/include/linux/buildid.h \
    $(wildcard include/config/VMCORE_INFO) \
  /home/nyasha/code/linux-flounder/include/linux/kmod.h \
  /home/nyasha/code/linux-flounder/include/linux/umh.h \
  /home/nyasha/code/linux-flounder/include/linux/gfp.h \
    $(wildcard include/config/ZONE_DMA) \
    $(wildcard include/config/ZONE_DMA32) \
    $(wildcard include/config/ZONE_DEVICE) \
    $(wildcard include/config/CONTIG_ALLOC) \
  /home/nyasha/code/linux-flounder/include/linux/mmzone.h \
    $(wildcard include/config/ARCH_FORCE_MAX_ORDER) \
    $(wildcard include/config/PAGE_BLOCK_MAX_ORDER) \
    $(wildcard include/config/CMA) \
    $(wildcard include/config/MEMORY_ISOLATION) \
    $(wildcard include/config/ZSMALLOC) \
    $(wildcard include/config/UNACCEPTED_MEMORY) \
    $(wildcard include/config/IOMMU_SUPPORT) \
    $(wildcard include/config/SWAP) \
    $(wildcard include/config/HUGETLB_PAGE) \
    $(wildcard include/config/TRANSPARENT_HUGEPAGE) \
    $(wildcard include/config/LRU_GEN_STATS) \
    $(wildcard include/config/LRU_GEN_WALKS_MMU) \
    $(wildcard include/config/MEMORY_FAILURE) \
    $(wildcard include/config/PAGE_EXTENSION) \
    $(wildcard include/config/DEFERRED_STRUCT_PAGE_INIT) \
    $(wildcard include/config/HAVE_MEMORYLESS_NODES) \
    $(wildcard include/config/SPARSEMEM_EXTREME) \
    $(wildcard include/config/SPARSEMEM_VMEMMAP_PREINIT) \
    $(wildcard include/config/HAVE_ARCH_PFN_VALID) \
  /home/nyasha/code/linux-flounder/include/linux/list_nulls.h \
  /home/nyasha/code/linux-flounder/include/linux/wait.h \
  /home/nyasha/code/linux-flounder/include/linux/seqlock.h \
    $(wildcard include/config/CC_IS_GCC) \
    $(wildcard include/config/GCC_VERSION) \
  /home/nyasha/code/linux-flounder/include/linux/mutex.h \
  /home/nyasha/code/linux-flounder/include/linux/debug_locks.h \
  /home/nyasha/code/linux-flounder/include/linux/pageblock-flags.h \
    $(wildcard include/config/HUGETLB_PAGE_SIZE_VARIABLE) \
  /home/nyasha/code/linux-flounder/include/linux/page-flags-layout.h \
  /home/nyasha/code/linux-flounder-out/include/generated/bounds.h \
  /home/nyasha/code/linux-flounder/include/linux/mm_types.h \
    $(wildcard include/config/HAVE_ALIGNED_STRUCT_PAGE) \
    $(wildcard include/config/SLAB_OBJ_EXT) \
    $(wildcard include/config/HUGETLB_PMD_PAGE_TABLE_SHARING) \
    $(wildcard include/config/SLAB_FREELIST_HARDENED) \
    $(wildcard include/config/USERFAULTFD) \
    $(wildcard include/config/ANON_VMA_NAME) \
    $(wildcard include/config/PER_VMA_LOCK) \
    $(wildcard include/config/HAVE_ARCH_COMPAT_MMAP_BASES) \
    $(wildcard include/config/MEMBARRIER) \
    $(wildcard include/config/FUTEX_PRIVATE_HASH) \
    $(wildcard include/config/ARCH_HAS_ELF_CORE_EFLAGS) \
    $(wildcard include/config/AIO) \
    $(wildcard include/config/MMU_NOTIFIER) \
    $(wildcard include/config/SPLIT_PMD_PTLOCKS) \
    $(wildcard include/config/IOMMU_MM_DATA) \
    $(wildcard include/config/KSM) \
    $(wildcard include/config/MM_ID) \
    $(wildcard include/config/CORE_DUMP_DEFAULT_ELF_HEADERS) \
  /home/nyasha/code/linux-flounder/include/linux/auxvec.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/auxvec.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/uapi/asm/auxvec.h \
  /home/nyasha/code/linux-flounder/include/linux/kref.h \
  /home/nyasha/code/linux-flounder/include/linux/rbtree.h \
  /home/nyasha/code/linux-flounder/include/linux/rcupdate.h \
    $(wildcard include/config/TINY_RCU) \
    $(wildcard include/config/RCU_STRICT_GRACE_PERIOD) \
    $(wildcard include/config/RCU_LAZY) \
    $(wildcard include/config/RCU_STALL_COMMON) \
    $(wildcard include/config/VIRT_XFER_TO_GUEST_WORK) \
    $(wildcard include/config/RCU_NOCB_CPU) \
    $(wildcard include/config/TASKS_RCU_GENERIC) \
    $(wildcard include/config/TASKS_RUDE_RCU) \
    $(wildcard include/config/TREE_RCU) \
    $(wildcard include/config/DEBUG_OBJECTS_RCU_HEAD) \
    $(wildcard include/config/PROVE_RCU) \
    $(wildcard include/config/ARCH_WEAK_RELEASE_ACQUIRE) \
  /home/nyasha/code/linux-flounder/include/linux/context_tracking_irq.h \
    $(wildcard include/config/CONTEXT_TRACKING_IDLE) \
  /home/nyasha/code/linux-flounder/include/linux/rcutree.h \
  /home/nyasha/code/linux-flounder/include/linux/maple_tree.h \
    $(wildcard include/config/MAPLE_RCU_DISABLED) \
    $(wildcard include/config/DEBUG_MAPLE_TREE) \
  /home/nyasha/code/linux-flounder/include/linux/rwsem.h \
    $(wildcard include/config/RWSEM_SPIN_ON_OWNER) \
    $(wildcard include/config/DEBUG_RWSEMS) \
  /home/nyasha/code/linux-flounder/include/linux/completion.h \
  /home/nyasha/code/linux-flounder/include/linux/swait.h \
  /home/nyasha/code/linux-flounder/include/linux/uprobes.h \
  /home/nyasha/code/linux-flounder/include/linux/timer.h \
    $(wildcard include/config/DEBUG_OBJECTS_TIMERS) \
    $(wildcard include/config/NO_HZ_COMMON) \
  /home/nyasha/code/linux-flounder/include/linux/ktime.h \
  /home/nyasha/code/linux-flounder/include/linux/jiffies.h \
  /home/nyasha/code/linux-flounder/include/vdso/jiffies.h \
  /home/nyasha/code/linux-flounder-out/include/generated/timeconst.h \
  /home/nyasha/code/linux-flounder/include/vdso/ktime.h \
  /home/nyasha/code/linux-flounder/include/linux/timekeeping.h \
    $(wildcard include/config/POSIX_AUX_CLOCKS) \
    $(wildcard include/config/GENERIC_CMOS_UPDATE) \
  /home/nyasha/code/linux-flounder/include/linux/clocksource_ids.h \
  /home/nyasha/code/linux-flounder/include/linux/debugobjects.h \
    $(wildcard include/config/DEBUG_OBJECTS) \
    $(wildcard include/config/DEBUG_OBJECTS_FREE) \
  /home/nyasha/code/linux-flounder/include/linux/workqueue.h \
    $(wildcard include/config/DEBUG_OBJECTS_WORK) \
    $(wildcard include/config/FREEZER) \
    $(wildcard include/config/WQ_WATCHDOG) \
  /home/nyasha/code/linux-flounder/include/linux/percpu_counter.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/mmu.h \
    $(wildcard include/config/ARM64_E0PD) \
  /home/nyasha/code/linux-flounder/include/linux/page-flags.h \
    $(wildcard include/config/PAGE_IDLE_FLAG) \
    $(wildcard include/config/ARCH_USES_PG_ARCH_2) \
    $(wildcard include/config/ARCH_USES_PG_ARCH_3) \
    $(wildcard include/config/MIGRATION) \
    $(wildcard include/config/HUGETLB_PAGE_OPTIMIZE_VMEMMAP) \
    $(wildcard include/config/DEBUG_KMAP_LOCAL_FORCE_MAP) \
  /home/nyasha/code/linux-flounder/include/linux/local_lock.h \
  /home/nyasha/code/linux-flounder/include/linux/local_lock_internal.h \
  /home/nyasha/code/linux-flounder/include/linux/zswap.h \
    $(wildcard include/config/ZSWAP) \
  /home/nyasha/code/linux-flounder/include/linux/memory_hotplug.h \
    $(wildcard include/config/ARCH_HAS_ADD_PAGES) \
    $(wildcard include/config/MEMORY_HOTREMOVE) \
  /home/nyasha/code/linux-flounder/include/linux/notifier.h \
  /home/nyasha/code/linux-flounder/include/linux/srcu.h \
    $(wildcard include/config/TINY_SRCU) \
    $(wildcard include/config/NEED_SRCU_NMI_SAFE) \
  /home/nyasha/code/linux-flounder/include/linux/rcu_segcblist.h \
  /home/nyasha/code/linux-flounder/include/linux/srcutree.h \
  /home/nyasha/code/linux-flounder/include/linux/rcu_node_tree.h \
    $(wildcard include/config/RCU_FANOUT) \
    $(wildcard include/config/RCU_FANOUT_LEAF) \
  /home/nyasha/code/linux-flounder-out/arch/arm64/include/generated/asm/mmzone.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/mmzone.h \
  /home/nyasha/code/linux-flounder/include/linux/topology.h \
    $(wildcard include/config/USE_PERCPU_NUMA_NODE_ID) \
    $(wildcard include/config/SCHED_SMT) \
    $(wildcard include/config/GENERIC_ARCH_TOPOLOGY) \
  /home/nyasha/code/linux-flounder/include/linux/arch_topology.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/topology.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/numa.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/numa.h \
    $(wildcard include/config/NUMA_EMU) \
  /home/nyasha/code/linux-flounder/include/asm-generic/topology.h \
  /home/nyasha/code/linux-flounder/include/linux/sysctl.h \
    $(wildcard include/config/SYSCTL) \
  /home/nyasha/code/linux-flounder/include/uapi/linux/sysctl.h \
  /home/nyasha/code/linux-flounder/include/linux/elf.h \
    $(wildcard include/config/ARCH_HAVE_EXTRA_ELF_NOTES) \
    $(wildcard include/config/ARCH_USE_GNU_PROPERTY) \
    $(wildcard include/config/ARCH_HAVE_ELF_PROT) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/elf.h \
    $(wildcard include/config/COMPAT_VDSO) \
  /home/nyasha/code/linux-flounder-out/arch/arm64/include/generated/asm/user.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/user.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/elf.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/elf-em.h \
  /home/nyasha/code/linux-flounder/include/linux/fs.h \
    $(wildcard include/config/FANOTIFY_ACCESS_PERMISSIONS) \
    $(wildcard include/config/READ_ONLY_THP_FOR_FS) \
    $(wildcard include/config/FS_POSIX_ACL) \
    $(wildcard include/config/CGROUP_WRITEBACK) \
    $(wildcard include/config/IMA) \
    $(wildcard include/config/FILE_LOCKING) \
    $(wildcard include/config/FSNOTIFY) \
    $(wildcard include/config/EPOLL) \
    $(wildcard include/config/FS_DAX) \
    $(wildcard include/config/BLOCK) \
    $(wildcard include/config/UNICODE) \
  /home/nyasha/code/linux-flounder/include/linux/fs/super.h \
  /home/nyasha/code/linux-flounder/include/linux/fs/super_types.h \
    $(wildcard include/config/QUOTA) \
    $(wildcard include/config/FS_ENCRYPTION) \
    $(wildcard include/config/FS_VERITY) \
  /home/nyasha/code/linux-flounder/include/linux/fs_dirent.h \
  /home/nyasha/code/linux-flounder/include/linux/errseq.h \
  /home/nyasha/code/linux-flounder/include/linux/list_lru.h \
  /home/nyasha/code/linux-flounder/include/linux/shrinker.h \
    $(wildcard include/config/SHRINKER_DEBUG) \
  /home/nyasha/code/linux-flounder/include/linux/xarray.h \
    $(wildcard include/config/XARRAY_MULTI) \
  /home/nyasha/code/linux-flounder/include/linux/sched/mm.h \
    $(wildcard include/config/MMU_LAZY_TLB_REFCOUNT) \
    $(wildcard include/config/ARCH_HAS_MEMBARRIER_CALLBACKS) \
    $(wildcard include/config/ARCH_HAS_SYNC_CORE_BEFORE_USERMODE) \
  /home/nyasha/code/linux-flounder/include/linux/sync_core.h \
    $(wildcard include/config/ARCH_HAS_PREPARE_SYNC_CORE_CMD) \
  /home/nyasha/code/linux-flounder/include/linux/sched/coredump.h \
  /home/nyasha/code/linux-flounder/include/linux/list_bl.h \
  /home/nyasha/code/linux-flounder/include/linux/bit_spinlock.h \
  /home/nyasha/code/linux-flounder/include/linux/percpu-rwsem.h \
  /home/nyasha/code/linux-flounder/include/linux/rcuwait.h \
  /home/nyasha/code/linux-flounder/include/linux/sched/signal.h \
    $(wildcard include/config/SCHED_AUTOGROUP) \
    $(wildcard include/config/BSD_PROCESS_ACCT) \
    $(wildcard include/config/TASKSTATS) \
  /home/nyasha/code/linux-flounder/include/linux/rculist.h \
    $(wildcard include/config/PROVE_RCU_LIST) \
  /home/nyasha/code/linux-flounder/include/linux/signal.h \
    $(wildcard include/config/DYNAMIC_SIGFRAME) \
    $(wildcard include/config/PROC_FS) \
  /home/nyasha/code/linux-flounder/include/linux/sched/jobctl.h \
  /home/nyasha/code/linux-flounder/include/linux/sched/task.h \
    $(wildcard include/config/HAVE_EXIT_THREAD) \
    $(wildcard include/config/ARCH_WANTS_DYNAMIC_TASK_STRUCT) \
    $(wildcard include/config/HAVE_ARCH_THREAD_STRUCT_WHITELIST) \
  /home/nyasha/code/linux-flounder/include/linux/uaccess.h \
    $(wildcard include/config/ARCH_HAS_SUBPAGE_FAULTS) \
    $(wildcard include/config/HARDENED_USERCOPY) \
  /home/nyasha/code/linux-flounder/include/linux/fault-inject-usercopy.h \
    $(wildcard include/config/FAULT_INJECTION_USERCOPY) \
  /home/nyasha/code/linux-flounder/include/linux/nospec.h \
  /home/nyasha/code/linux-flounder/include/linux/ucopysize.h \
    $(wildcard include/config/HARDENED_USERCOPY_DEFAULT_ON) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/uaccess.h \
    $(wildcard include/config/CC_HAS_ASM_GOTO_OUTPUT) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/kernel-pgtable.h \
    $(wildcard include/config/RELOCATABLE) \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/asm-extable.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/mte.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/extable.h \
    $(wildcard include/config/BPF_JIT) \
  /home/nyasha/code/linux-flounder/include/asm-generic/access_ok.h \
    $(wildcard include/config/ALTERNATE_USER_ADDRESS_SPACE) \
  /home/nyasha/code/linux-flounder/include/linux/cred.h \
  /home/nyasha/code/linux-flounder/include/linux/capability.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/capability.h \
  /home/nyasha/code/linux-flounder/include/linux/key.h \
    $(wildcard include/config/KEY_NOTIFICATIONS) \
    $(wildcard include/config/NET) \
  /home/nyasha/code/linux-flounder/include/linux/assoc_array.h \
    $(wildcard include/config/ASSOCIATIVE_ARRAY) \
  /home/nyasha/code/linux-flounder/include/linux/sched/user.h \
    $(wildcard include/config/VFIO_PCI_ZDEV_KVM) \
    $(wildcard include/config/IOMMUFD) \
    $(wildcard include/config/WATCH_QUEUE) \
  /home/nyasha/code/linux-flounder/include/linux/ratelimit.h \
  /home/nyasha/code/linux-flounder/include/linux/pid.h \
  /home/nyasha/code/linux-flounder/include/linux/posix-timers.h \
  /home/nyasha/code/linux-flounder/include/linux/alarmtimer.h \
    $(wildcard include/config/RTC_CLASS) \
  /home/nyasha/code/linux-flounder/include/linux/hrtimer.h \
    $(wildcard include/config/HIGH_RES_TIMERS) \
    $(wildcard include/config/TIME_LOW_RES) \
    $(wildcard include/config/TIMERFD) \
  /home/nyasha/code/linux-flounder/include/linux/hrtimer_defs.h \
  /home/nyasha/code/linux-flounder/include/linux/timerqueue.h \
  /home/nyasha/code/linux-flounder/include/linux/rcuref.h \
  /home/nyasha/code/linux-flounder/include/linux/rcu_sync.h \
  /home/nyasha/code/linux-flounder/include/linux/quota.h \
    $(wildcard include/config/QUOTA_NETLINK_INTERFACE) \
  /home/nyasha/code/linux-flounder/include/uapi/linux/dqblk_xfs.h \
  /home/nyasha/code/linux-flounder/include/linux/dqblk_v1.h \
  /home/nyasha/code/linux-flounder/include/linux/dqblk_v2.h \
  /home/nyasha/code/linux-flounder/include/linux/dqblk_qtree.h \
  /home/nyasha/code/linux-flounder/include/linux/projid.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/quota.h \
  /home/nyasha/code/linux-flounder/include/linux/unicode.h \
  /home/nyasha/code/linux-flounder/include/linux/dcache.h \
  /home/nyasha/code/linux-flounder/include/linux/rculist_bl.h \
  /home/nyasha/code/linux-flounder/include/linux/lockref.h \
    $(wildcard include/config/ARCH_USE_CMPXCHG_LOCKREF) \
  /home/nyasha/code/linux-flounder/include/linux/stringhash.h \
    $(wildcard include/config/DCACHE_WORD_ACCESS) \
  /home/nyasha/code/linux-flounder/include/linux/hash.h \
    $(wildcard include/config/HAVE_ARCH_HASH) \
  /home/nyasha/code/linux-flounder/include/linux/vfsdebug.h \
    $(wildcard include/config/DEBUG_VFS) \
  /home/nyasha/code/linux-flounder/include/linux/wait_bit.h \
  /home/nyasha/code/linux-flounder/include/linux/kdev_t.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/kdev_t.h \
  /home/nyasha/code/linux-flounder/include/linux/path.h \
  /home/nyasha/code/linux-flounder/include/linux/radix-tree.h \
  /home/nyasha/code/linux-flounder/include/linux/semaphore.h \
  /home/nyasha/code/linux-flounder/include/linux/fcntl.h \
    $(wildcard include/config/ARCH_32BIT_OFF_T) \
  /home/nyasha/code/linux-flounder/include/uapi/linux/fcntl.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/uapi/asm/fcntl.h \
  /home/nyasha/code/linux-flounder/include/uapi/asm-generic/fcntl.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/openat2.h \
  /home/nyasha/code/linux-flounder/include/linux/migrate_mode.h \
  /home/nyasha/code/linux-flounder/include/linux/delayed_call.h \
  /home/nyasha/code/linux-flounder/include/linux/ioprio.h \
  /home/nyasha/code/linux-flounder/include/linux/sched/rt.h \
  /home/nyasha/code/linux-flounder/include/linux/iocontext.h \
    $(wildcard include/config/BLK_ICQ) \
  /home/nyasha/code/linux-flounder/include/uapi/linux/ioprio.h \
  /home/nyasha/code/linux-flounder/include/linux/mount.h \
  /home/nyasha/code/linux-flounder/include/linux/mnt_idmapping.h \
  /home/nyasha/code/linux-flounder/include/linux/slab.h \
    $(wildcard include/config/FAILSLAB) \
    $(wildcard include/config/KFENCE) \
    $(wildcard include/config/SLUB_TINY) \
    $(wildcard include/config/SLUB_DEBUG) \
    $(wildcard include/config/SLAB_BUCKETS) \
    $(wildcard include/config/KVFREE_RCU_BATCHED) \
  /home/nyasha/code/linux-flounder/include/linux/percpu-refcount.h \
  /home/nyasha/code/linux-flounder/include/linux/rw_hint.h \
  /home/nyasha/code/linux-flounder/include/linux/file_ref.h \
  /home/nyasha/code/linux-flounder/include/uapi/linux/fs.h \
  /home/nyasha/code/linux-flounder/include/linux/kobject.h \
    $(wildcard include/config/UEVENT_HELPER) \
    $(wildcard include/config/DEBUG_KOBJECT_RELEASE) \
  /home/nyasha/code/linux-flounder/include/linux/sysfs.h \
  /home/nyasha/code/linux-flounder/include/linux/kernfs.h \
    $(wildcard include/config/KERNFS) \
  /home/nyasha/code/linux-flounder/include/linux/idr.h \
  /home/nyasha/code/linux-flounder/include/linux/kobject_ns.h \
  /home/nyasha/code/linux-flounder/include/linux/moduleparam.h \
    $(wildcard include/config/ALPHA) \
    $(wildcard include/config/PPC64) \
  /home/nyasha/code/linux-flounder/include/linux/rbtree_latch.h \
  /home/nyasha/code/linux-flounder/include/linux/error-injection.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/error-injection.h \
  /home/nyasha/code/linux-flounder/include/linux/dynamic_debug.h \
  /home/nyasha/code/linux-flounder/arch/arm64/include/asm/module.h \
  /home/nyasha/code/linux-flounder/include/asm-generic/module.h \
    $(wildcard include/config/HAVE_MOD_ARCH_SPECIFIC) \
  /home/nyasha/code/linux-flounder/include/linux/export-internal.h \
    $(wildcard include/config/PARISC) \

sfio.mod.o: $(deps_sfio.mod.o)

$(deps_sfio.mod.o):

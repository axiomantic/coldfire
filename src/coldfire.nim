## The Nim entry module of the `mcf5407` project.
##
## The build passes `--nimMainPrefix:mcf5407_` for this module. A second Nim
## library passes its own prefix and exports its own
## `<component>_runtime_init`, and nothing else changes.

# The core submodules. The entry module imports them so that the compiler
# compiles them into this library; it never names their symbols itself. The
# `UnusedImport` warning is therefore expected and is masked. The exported
# `mcf5407_*` state functions the submodules carry are reached from C by name
# (see `include/mcf5407.h` and `tests/abi_smoke.cpp`).
{.push warning[UnusedImport]: off.}
import coldfire/alu
import coldfire/cpu
import coldfire/decode
import coldfire/decode_types
import coldfire/ea
import coldfire/logic
import coldfire/machine
import coldfire/move
import coldfire/state
import coldfire/intc
import coldfire/timer
import coldfire/uart
import coldfire/mbus
import coldfire/sim
{.pop.}

# The latch. It is imported outside the pushed warning mask because this
# module names its symbols below.
import coldfire/latch

# ---------------------------------------------------------------------------
# The pragma set of every symbol this project publishes.
#
# Each exported procedure carries `{.exportc: "<c name>", mcf5407Abi.}` and
# nothing less. `mcf5407Abi` holds `cdecl` and `dynlib` together, so that the
# set is written once and no later edit can supply half of it.
#
# `dynlib` is load-bearing. Measured on Nim 2.2.10, a procedure declared
# `{.exportc, cdecl.}` alone translates to `N_LIB_PRIVATE`, and `nimbase.h`
# defines that as `__attribute__((visibility("hidden")))` for gcc and clang.
# The same procedure with `dynlib` translates to `N_LIB_EXPORT`, which is
# `__attribute__((visibility("default")))`.
#
# A hidden symbol still reports as `T` in `nm` output over the static archive,
# so `nm libmcf5407.a` cannot find this fault. The fault appears only when the
# archive goes into a shared object, which is the delivery form. The plugin
# then exports nothing, and the host cannot reach the core.
#
# `cmake/Nim.cmake` step 4a builds a shared object at configure time and reads
# its symbol table. A published symbol the object defines and does not export
# fails the configure step. The check reads the linker's answer and no Nim
# macro, so a Nim release that renames `N_LIB_EXPORT` changes nothing about it.
#
# `include/mcf5407.h` describes the set as `{.exportc, cdecl.}`, without
# `dynlib`. This file is the one the compiler reads.
{.pragma: coldfireAbi, cdecl, dynlib.}

# ---------------------------------------------------------------------------
# `coldfire_NimMain` is the runtime initializer that `--nimMainPrefix:coldfire_`
# renames. The prefix is what lets a second Nim library live in the same
# binary, because the collision is on the default names alone.
proc coldfire_NimMain() {.importc: "coldfire_NimMain", cdecl, gcsafe,
                          raises: [].}

# ---------------------------------------------------------------------------
# `cf_runtime_init` - the published entry point.
#
# The mechanism is in `coldfire/latch` and not here. Two other modules ask the
# same latch whether the runtime was abandoned before they allocate, and a
# suite drives it directly; that module states why neither can reach it
# through this one.

proc cfRuntimeInit*(): cint {.exportc: "cf_runtime_init",
                              coldfireAbi.} =
  ## Runs the Nim runtime's initializer once and reports whether it succeeded.
  ##
  ## C++ never names `coldfire_NimMain`. It calls this procedure instead.
  ##
  ## The return is 1 for usable and 0 for not, which is the convention every
  ## other `int` in `include/coldfire.h` already uses.
  if runtimeInitOnce(runtimeLatch, coldfire_NimMain):
    cint(1)
  else:
    cint(0)


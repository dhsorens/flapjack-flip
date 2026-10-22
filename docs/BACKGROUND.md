# Background

This document explains the problem behind the challenge: what the input is, what it
runs on, what "the same behaviour" means, and why the success criteria are what
they are. [`PROMPT.md`](../PROMPT.md) has the task itself.

## 1. The pieces

**Pancake** is a small, low-level systems language from the CakeML project. It has
64-bit words, structs ("shapes") of words, local and global variables, `while`
loops, functions, exceptions, and explicit memory access (`lds 1 a` / `st a, v` for
words, `ld8` / `st8` for bytes, `ld32` for 32-bit loads). It has no heap
allocator, no strings and no I/O of its own. Programs talk to the outside world
only through **FFI calls**: `@name(conf_ptr, conf_len, array_ptr, array_len)`.

```
fun 1 main() {
  @read(0, 0, @base, 8);     // fill 8 bytes at the start of memory with input
  @write(0, 0, @base, 8);    // send the same 8 bytes back out
  return 0;
}
```

**Flapjack** ([pirapira/flapjack](https://github.com/pirapira/flapjack)) is a Lean 4
port of CakeML's verified Pancake compiler. Its parser and static checker accept
Pancake source. `RiscV.NativeSource.compile` turns that source into RV64IM machine
code. `nativeCLIOutput_correct` proves that the code it emits behaves like the
source, under CakeML's installation assumptions. We use Flapjack at the pinned
revision in `lakefile.toml`.

**riscv-zkvm** ([Verified-zkEVM/riscv-zkvm](https://github.com/Verified-zkEVM/riscv-zkvm))
is a computable RV64IM machine model in Lean (`RiscvZkvm.Rv64`: `Instr`,
`MachineState`, `step`). It is proved equivalent, instruction by instruction, to
the official Sail RISC-V specification. Here `RiscvZkvm.Rv64.step` is *the*
meaning of a RISC-V instruction. riscv-zkvm also provides the instruction decoder
(`RiscvZkvm.Interpreter.decode`).

**FlapjackFlip** (this repository) goes the other way: from the RISC-V code back to
Pancake.

```
                    Flapjack                  install + riscv-zkvm step
  source.pnk  ───────────────────►  Image  ───────────────────────────►  FFI trace + exit
       ▲                              │
       │        FlapjackFlip          │
       └──────────────────────────────┘
                (your decompiler)
```

## 2. The input: an `Image`

`FlapjackFlip.Image` is a stripped Flapjack binary. It has three fields:

| field | contents |
|---|---|
| `code` | the machine code bytes, exactly as `flapjack-compile --hex` prints them; execution starts at byte 0 |
| `bitmaps` | the stack-frame bitmaps Flapjack emits beside the code (the code reads them at run time) |
| `ffiNames` | the FFI names, in FFI index order |

On disk, an image is a short text file:

```
flapjack-flip image v1
ffi write
bitmaps 0000000000000004
code b3 e0 d6 00 b3 80 b0 40 ...
```

Function names, function boundaries, and anything else from the source are gone.
The FFI names stay, because they are observable (they appear in the trace). Real
executables keep the names of their dynamic imports for the same reason.

`lake exe flapjack-flip --disasm IMAGE` prints the decoded instructions.

## 3. Running an image

`FlapjackFlip/Machine.lean` defines how an image runs. It realises CakeML's RISC-V
conventions (`isRiscvMachineConfig`, `panInstalled` in Flapjack) as one concrete
machine state of riscv-zkvm:

| what | where |
|---|---|
| code | starts at `0x8001_0000`, in riscv-zkvm's code memory (not readable or writable as data) |
| halt entry | `code − 16` |
| cache-clear entry | `code − 32` |
| FFI entry *i* | `code − 16·(i+3)` |
| bitmaps | `0xa000_0000` |
| heap | `0xa010_0000 – 0xa050_0000` (4 MiB); the first five words hold the pointers `panInstalled` requires |
| stack | `0xa050_0000 – 0xa090_0000` (4 MiB) |
| registers at entry | `pc = a0 = code`, `a1 = heap`, `a2 = stack`, `a3 = stack end`, others 0 |

The entry points hold no instructions. When the pc reaches one, the semantics acts
the way CakeML's target semantics (`targetSemScript.sml`) does:

- **halt.** The run ends: `success` if `a0 = 0`, otherwise `resourceLimitHit`
  (out of memory).
- **FFI *i*.** Read the configuration bytes `[a0, a0+a1)` and the array
  `[a2, a2+a3)`. Hand them to the oracle via Flapjack's `callFFIHOL`, which also
  records an event `(name, conf, array-before, array-after)`. Write the returned
  array back and continue at `ra`.
- **cache-clear.** The run fails. Pancake never uses it.

Every other pc is one `RiscvZkvm.Rv64.step`. If `step` returns `none` (illegal or
out-of-range memory access, undecodable instruction, `ecall`, …), the run **fails**.

`observe img oracle s n` runs `n` steps and returns an `Observation`: the events so
far, plus a status of running, halted (with an outcome) or failed.

## 4. Behaviour, and "the same behaviour"

The only things the outside world can see of a Pancake program are:

1. the sequence of FFI events (name, configuration bytes, array before and after);
2. whether and how it stops: normal halt, out of memory, a final FFI outcome,
   a failure, or never.

The return value of `main` is **not** observable. CakeML's Pancake semantics maps
every `return` from `main` to the same `Terminate Success`. The machine level agrees,
because Flapjack always halts with `a0 = 0`. So a program with no FFI calls is
indistinguishable from `fun 1 main() { return 0; }`. Every test program therefore
does I/O. `flip-check build` rejects a test that doesn't.

`FlapjackFlip/Spec.lean` makes "same behaviour" precise:

- `Refines a b`: for **every** oracle, every trace prefix that `a` produces is also
  produced by `b`. If `a` stops, `b` stops the same way with the same events. The
  one exception is out-of-memory: as in CakeML's own theorems, hitting the
  resource limit only promises that the events before it were right. How much stack
  a program needs depends on how it was compiled, so nothing stronger can be
  proved.
- `Equivalent a b := Refines a b ∧ Refines b a`.
- `DecompilerSound decompile`: whenever `decompile img = .ok src`, `src` compiles
  with Flapjack to some `img'`, and `Equivalent img img'`.

Quantifying over every oracle is what "for all inputs" means. The oracle sees every
FFI call and may answer anything (or end the run).

## 5. The tests

Tests live in `tests/<name>/`:

- `source.pnk`: the program the test was compiled from. Only the judge reads it, for
  the token budget.
- `image.fjimg`: the binary your decompiler receives.
- `expected.txt`: what the binary does on each test input, for reference.

There are 20 hand-written tests (`00_hello` … `19_early_return`) and 100 random ones
(`gen_0_*`, from `scripts/gen_tests.py 0 100 tests`). Together they cover
arithmetic, shifts, signed/unsigned comparisons, branches, loops with
`break`/`continue`, calls, recursion, globals, byte/word memory, struct returns,
exceptions, several FFI names and configuration bytes.

The test oracle (`FlapjackFlip.Harness.oracle`) treats every FFI name alike. A call
with an array of length *n* consumes the next *n* bytes of an input stream and
returns them as the new array contents (zeros once the stream is exhausted). A
program reads input through the arrays it gets back, and writes output through the
bytes it passes in. Each test runs on five input streams (`Harness.inputs`).

## 6. Why the criteria look like this

Each criterion closes a loophole the others leave open.

- **The theorem without the tests** is satisfied by a decompiler that always
  returns `.error`. That is the starting point.
- **The tests without the theorem** are satisfied by a decompiler that is merely
  right on 600 inputs. The challenge is a *verified* decompiler.
- **The theorem and the visible tests** are satisfied by a lookup table: "if the
  image equals the compiled form of one of these 120 known programs, return that
  program". That is even *provably sound*, since the source does compile to that
  image. The hidden tests from a secret generator seed rule this out.
- **All of the above** are satisfied by an "emulator decompiler": emit Pancake source
  that stores the machine code in memory and interprets it. That is correct, general
  and verifiable, and useless as a decompiler. The token budget (4× the original
  source) rules it out.

## 7. Where to start

**Prior art.** Magnus Myreen's *decompilation into logic*
([TR-765](https://www.cl.cam.ac.uk/techreports/UCAM-CL-TR-765.html)) turns machine
code into tail-recursive functions plus a certificate theorem.
[dhsorens/riscv-decomp](https://github.com/dhsorens/riscv-decomp) implements that
method over riscv-zkvm: Hoare-style triples over `RiscvZkvm.Rv64.step`, loop rules
without fuel, and a CFG extractor. It is worth reading, and may be worth depending
on.

**Shape of a decompiler.** Flapjack's output is very regular. It comes from one
compiler, with one register allocator, one calling convention and one stack layout.
A practical pipeline is: disassemble, recover the control-flow graph and function
boundaries, undo the calling convention and the stack frame, structure the control
flow (loops, ifs, exceptions), recover expressions, then print Pancake.

**Shape of a proof.** Two broad routes:

1. *Prove the decompiler correct directly.* Relate the binary to the Pancake
   semantics of the output (`Flapjack.Pancake.Semantics`). Then use Flapjack's
   `nativeCLIOutput_correct` to get from the source to its compiled form.

   Caveat: that theorem is stated over Flapjack's own L3-derived RISC-V model, not
   riscv-zkvm's. You would also need a simulation between the two models, for the
   instructions Flapjack emits and for this installation.

2. *Translation validation.* Have `decompile` recompile its own output and run a
   checker that compares the two binaries, then prove the *checker* sound.
   `decompile` may call `FlapjackFlip.compile`, which is computable. This keeps the
   proof about two programs on one machine model, at the cost of a checker that
   must be complete enough to pass the tests.

Either way, expect the proof to be most of the work.

## 8. Things that will bite

- **Pancake syntax.** A `-` immediately before a digit is part of the literal, so
  write `x - 1`, not `x-1`. Ordinary memory has 8-, 32- and 64-bit loads, but only
  8- and 64-bit stores in practice: `ld16`/`st16` are shared-memory operations, and
  `st32` currently trips Flapjack's scope checker. Shift amounts are constants.
  When in doubt, `lake exe flip-check build` on a scratch directory tells you
  whether Flapjack accepts a program.
- **Your output must re-compile.** The judge runs Flapjack's static checker too. For
  example, every `var` must be initialised and every function must return.
- **Shared memory is out of scope.** Programs using `!ld`/`!st` are rejected by
  `FlapjackFlip.compile`.
- **FFI calls preserve all registers here.** CakeML allows an FFI call to clobber
  every register except `s8`–`s10` (x24–x26). This semantics picks the
  "clobber nothing" behaviour, which is one of the allowed ones. Correct
  Flapjack code cannot tell the difference.
- **Speed.** riscv-zkvm's `MachineState` memory is a function, so each store adds a
  closure layer. That is fine for the tests: the longest runs for about 70 000
  steps. Running millions of steps will be slow.
- **Building.** The first build compiles the part of Flapjack the harness needs
  (about 6 minutes on a laptop). Importing Flapjack's correctness proofs, for
  example `Flapjack.Pancake.Proofs.PanToTarget.NativeCLICorrect`, compiles about
  4,000 more modules: plan for most of an hour, once. Run `lake exe cache get`
  first to download Mathlib's build instead of compiling it.

## 9. Code map

| file | role | frozen |
|---|---|---|
| `FlapjackFlip/Image.lean` | the binary format | yes |
| `FlapjackFlip/Compile.lean` | Pancake source → `Image`, via Flapjack | yes |
| `FlapjackFlip/Machine.lean` | installing and running an image on riscv-zkvm | yes |
| `FlapjackFlip/Spec.lean` | `Refines`, `Equivalent`, `DecompilerSound` | yes |
| `FlapjackFlip/Harness.lean` | test oracle, inputs, fuel, token budget, `checkCase` | yes |
| `FlapjackFlip/Decompile.lean` | **the decompiler** | no |
| `FlapjackFlip/Soundness.lean` | **its proof** | no |
| `Main.lean` | `flapjack-flip` CLI | no |
| `Check.lean` | `flip-check` test runner | yes |
| `Acceptance.lean` | the acceptance theorem | yes |
| `scripts/gen_tests.py` | random test generator | yes |
| `scripts/accept.sh` | runs criteria 1–4 | yes |

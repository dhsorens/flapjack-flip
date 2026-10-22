# FlapjackFlip

A challenge: build a **formally verified decompiler** in Lean 4, from RISC-V binaries
produced by the [Flapjack](https://github.com/pirapira/flapjack) Pancake compiler back
to Pancake source. The binaries run on the
[riscv-zkvm](https://github.com/Verified-zkEVM/riscv-zkvm) machine model.

- **[PROMPT.md](PROMPT.md)**: the task and the success criteria.
- **[docs/BACKGROUND.md](docs/BACKGROUND.md)**: what the binaries are, how they run,
  what "the same behaviour" means, and where to start.

## Quick start

```bash
lake exe cache get          # Mathlib's prebuilt files
lake build                  # first build compiles Flapjack: ~6 minutes
lake exe flip-check         # run the decompiler on the 120 tests in tests/
```

To try one binary by hand:

```bash
lake exe flapjack-flip --disasm tests/00_hello/image.fjimg   # decoded instructions
lake exe flapjack-flip tests/00_hello/image.fjimg            # decompile
lake exe flip-check run tests/00_hello/image.fjimg           # what the binary does
```

`scripts/accept.sh` checks everything a submission needs except the hidden tests.

## Status

The starting decompiler disassembles and then gives up. It is proved sound, and it
passes 0 of 120 tests.

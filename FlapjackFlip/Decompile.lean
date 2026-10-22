/-
  FlapjackFlip.Decompile

  THE DECOMPILER. This is the file to work on.

  The starting point only disassembles: it turns the code bytes into
  `RiscvZkvm.Rv64.Instr`s and then gives up. Giving up is always sound, which is why
  `FlapjackFlip.Soundness` can already prove it correct. It passes no tests.
-/

import RiscvZkvm.Interpreter.Decode
import FlapjackFlip.Image

namespace FlapjackFlip

open RiscvZkvm.Rv64

/-- The instructions of an image, in order. `none` marks a word the riscv-zkvm decoder
does not understand. -/
def disassemble (img : Image) : List (Option Instr) :=
  (List.range (img.code.length / 4)).map fun k =>
    match (img.code.drop (4 * k)).take 4 with
    | [b0, b1, b2, b3] => RiscvZkvm.Interpreter.decode (b3 ++ b2 ++ b1 ++ b0)
    | _ => none

/-- Decompile a Flapjack binary to Pancake source text, or explain why not. -/
def decompile (img : Image) : Except String String :=
  let instrs := disassemble img
  .error s!"not implemented yet ({instrs.length} instructions, {img.ffiNames.length} FFI names)"

end FlapjackFlip

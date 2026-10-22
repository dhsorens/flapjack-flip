/-
  FlapjackFlip.Soundness

  The proof that `decompile` is correct. Work on this file together with
  `FlapjackFlip.Decompile`.

  The theorem's name and statement must not change: `Acceptance.lean` refers to it.
-/

import FlapjackFlip.Decompile
import FlapjackFlip.Spec

namespace FlapjackFlip

/-- The starting decompiler never returns source, so there is nothing to show. -/
theorem decompile_sound : DecompilerSound decompile := by
  intro img src h
  simp [decompile] at h

end FlapjackFlip

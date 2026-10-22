import FlapjackFlip

/-!
The acceptance theorem. FROZEN: see `PROMPT.md`, criterion 2.

`scripts/accept.sh` checks the axioms printed below.
-/

open FlapjackFlip in
theorem acceptance : DecompilerSound decompile := decompile_sound

#print axioms acceptance

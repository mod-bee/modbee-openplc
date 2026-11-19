(* I_LocalChoice — a block's panel choices beyond start / stop (Low / High, Forward / Reverse, Pos1..3, Halt),
found by FB_LocalControl on its equipment; Choose acts in Hand only. *)

INTERFACE I_LocalChoice EXTENDS __SYSTEM


.IQueryInterface
  METHOD Choose : BOOL             // TRUE: the block has this choice
    VAR_INPUT
      eLocalChoice : E_LocalChoice;    // the local selection: Low, High, Forward, Reverse, Pos1..Pos3 or Halt
    END_VAR
  END_METHOD

END_INTERFACE
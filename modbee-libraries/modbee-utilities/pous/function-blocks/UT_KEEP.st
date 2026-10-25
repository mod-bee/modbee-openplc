(* UT_KEEP — when a block keeps its own settings and totals over a power cut.

Every block with a Data record keeps a retained copy of its settings (and of
its totals, if it has any) inside itself: VAR RETAIN keptSet / keptTot. This
piece says WHEN to copy; the block does the copies (IEC has no generic struct
parameter):

keep(TotalsNow := totalsChanged);
IF keep.RestoreSet THEN Data.set := keptSet; END_IF;
IF keep.SaveSet THEN keptSet := Data.set; END_IF;
IF keep.RestoreTot THEN Data.tot := keptTot; END_IF;
IF keep.SaveTot THEN keptTot := Data.tot; END_IF;

First boot (nothing kept yet, a cold restart, persistent storage off): the
project's values in Data.set are taken and saved (FirstBoot). Every power-up
after that: the kept settings and totals go back into Data before anything
else runs - the PLC's settings always win (decision 28). While running, the
settings copy is brought up to date once a second; the retained store writes
only when the bytes changed, so an unchanged setting costs no flash write.
Totals are copied every TotalsEvery (default one hour, decision 33) and at
once on TotalsNow (a reset, a preset, a day closed).

The power-up flag is NON_RETAIN: a block instance declared RETAIN by mistake
still sees its power-up. *)

FUNCTION_BLOCK UT_KEEP
  VAR_INPUT
    TotalsEvery : TIME := T#1h; (* totals copy period (<= 0: only on TotalsNow) *)
    TotalsNow : BOOL; (* copy the totals now (reset, preset, day closed) *)
  END_VAR
  VAR_OUTPUT
    PowerUp : BOOL; (* one scan: the first scan after power-up / upload *)
    RestoreSet : BOOL; (* one scan: copy the kept settings into Data.set *)
    SaveSet : BOOL; (* copy Data.set into the kept copy *)
    RestoreTot : BOOL; (* one scan: copy the kept totals into Data.tot *)
    SaveTot : BOOL; (* copy Data.tot into the kept copy *)
    FirstBoot : BOOL; (* one scan: nothing was kept, the project's values were taken *)
  END_VAR
  VAR RETAIN
    valid : BOOL; (* a kept copy exists *)
  END_VAR
  VAR NON_RETAIN
    started : BOOL;
    lastSet : TIME;
    lastTot : TIME;
  END_VAR
  VAR
    now : TIME;
  END_VAR


now := TIME();
PowerUp := NOT started;
RestoreSet := FALSE;
RestoreTot := FALSE;
SaveSet := FALSE;
SaveTot := FALSE;
FirstBoot := FALSE;
IF PowerUp THEN
  started := TRUE;
  lastSet := now;
  lastTot := now;
  IF valid THEN
    RestoreSet := TRUE;
    RestoreTot := TRUE;
  ELSE
    FirstBoot := TRUE;
    SaveSet := TRUE;
    SaveTot := TRUE;
    valid := TRUE;
  END_IF;
  RETURN;
END_IF;
IF now - lastSet >= T#1s THEN
  SaveSet := TRUE;
  lastSet := now;
END_IF;
IF TotalsNow OR (TotalsEvery > T#0s AND now - lastTot >= TotalsEvery) THEN
  SaveTot := TRUE;
  lastTot := now;
END_IF;

END_FUNCTION_BLOCK
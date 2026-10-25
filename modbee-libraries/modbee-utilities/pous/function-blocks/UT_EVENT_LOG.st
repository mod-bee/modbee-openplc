(* UT_EVENT_LOG — the last N events (trips, stops, end reasons) with their
time, newest first, for "what happened overnight". Optionally kept over a
power cut.

Call it once per source per scan, all calls on the same instance, Buffer,
Sources and Data (as UT_MSG_QUEUE):
  Log(Code := 0, Stop := Pump1.stopReason, Src := 1,
      Buffer := EvLog, Sources := EvSrc, Data := EvCfg);
  Log(Fault := Pump1.lastFault, Count := Pump1.trips, Src := 2, ...);
(Wire Code in at least one call, 0 if you have no code of your own.)
An event is codes, not words: its stop reason (UT_STOP), its fault
(UT_FAULT) and a code of your own (INT). The HMI or SCADA shows the words.
A call logs one event (Code, Stop, Fault) when, for its source:
  - New has a rising edge (wire any event pulse, e.g. a stop), or
  - Code changes to a value other than 0, Stop to one other than
    UT_STOP_NONE, or Fault to one other than UT_F_NONE, or
  - Count changes (wire a counter such as a record's trips: every trip is
    logged, also the same one again).
One of these in a call gives one event. The calls share one instance, so
the block sets its pins back to their defaults after each call (Code 0,
Stop UT_STOP_NONE, Fault UT_F_NONE, New FALSE, Count 0, Src 1, Clock unwired): a pin a call leaves
unwired never carries another call's value. What a source shows at its first
call after a power-up is its starting point, not an event (as a command
never acts on the first scan); the power-up event (source 0) marks that moment. Sources[Src]
keeps what was last seen from each source (the block writes it).

Buffer is the log, newest first: Buffer's first element is the newest
event; a new one moves the others down, and the oldest falls off a full
log (counted in `lost`). Each event has its time (Clock, optional; unwired:
blank - the boards have no real-time clock), source, codes and a running
number `seq` (0 = an empty slot). logPowerUp adds a power-up event
(source 0, no codes) at every power-up.

Kept over a power cut (retained TRUE, the default, and saveEvery above 0):
the block's own kept copy (up to 16 events) gets a copy of the log. The
first event after a quiet spell (no save for saveEvery) is copied at once,
with any others of the same scan; later ones wait until saveEvery has
passed since that copy, so a burst of events writes the controller's
storage once. The power-up event is copied at once and does not start
the wait (one copy per power-up), so the first event after a power-up is
also kept at once. At power-up the log is read back from the kept copy.
retained FALSE or saveEvery T#0s: nothing is kept and the log starts
empty. cmdClear empties the log (and the kept copy at once). The newest
event is in sts.last (published on change); Buffer is Detail.

RAM is what you declare: one UT_EVENT per slot (twice when kept), one
UT_EVENT_SRC per source. Every loop is bounded by the array sizes. One
instance is called many times in a scan (TIME() is the same for the whole
scan): NewEvent stays on for the rest of the scan in which an event came,
and the command and the saving act once per scan. *)

FUNCTION_BLOCK UT_EVENT_LOG
  VAR_INPUT
    Code : INT; (* a code of your own (0 = none) *)
    Stop : UT_STOP; (* a stop reason (e.g. Pump1.stopReason) *)
    Fault : UT_FAULT; (* a fault (e.g. Pump1.lastFault) *)
    New : BOOL; (* rising edge: log the codes now *)
    Count : UDINT; (* optional counter (e.g. Pump1.trips): each change logs the codes *)
    Src : INT := 1; (* source number: the element of Sources this call uses *)
    Clock : DT := DT#1970-01-01-00:00:00; (* a real-time clock (optional); unwired = no clock: stamps stay blank *)
  END_VAR
  VAR_OUTPUT
    Events : INT; (* events in the log *)
    NewEvent : BOOL; (* on for the scan in which an event was logged *)
    BadSetting : BOOL;
  END_VAR
  VAR RETAIN
    saved : ARRAY [1..16] OF UT_EVENT; (* the kept copy (a block cannot size its own variables from the caller, 6.5.3) *)
    keptSet : UT_EVENT_LOG_SET;
    keptGood : BOOL;
  END_VAR
  VAR_IN_OUT
    Buffer : ARRAY [*] OF UT_EVENT; (* the log, newest first: as many slots as you declare *)
    Sources : ARRAY [*] OF UT_EVENT_SRC; (* what was last seen per source, index = Src (the block writes it) *)
    Data : UT_EVENT_LOG_DATA;
  END_VAR
  VAR
    kp : UT_KEEP;
    setOk : BOOL := TRUE;
    started : BOOL;
    tCur : TIME;
    tLast : TIME;
    newScan : BOOL;
    clk : DT;
    blo : DINT;
    bhi : DINT;
    nb : DINT; (* slots *)
    vlo : DINT;
    vhi : DINT;
    nv : DINT; (* saved slots *)
    slo : DINT;
    shi : DINT;
    keep : BOOL; (* the log is kept over a power cut *)
    cnt : DINT; (* events in the log *)
    seqNext : UDINT; (* the next event's running number *)
    dirty : BOOL; (* the log changed since the last save *)
    tSave : TIME;
    quiet : BOOL; (* no save within saveEvery: the next change is saved at once *)
    puOnly : BOOL; (* the only unsaved change is the power-up event (its save starts no wait) *)
    clearSeen : BOOL;
    take : BOOL;
    i : DINT;
    m : DINT;
    evCode : INT;
    evStop : UT_STOP;
    evFault : UT_FAULT;
    evSrc : INT;
  END_VAR


tCur := TIME();
blo := LOWER_BOUND(Buffer, 1);
bhi := UPPER_BOUND(Buffer, 1);
nb := bhi - blo + 1;
IF nb < 0 THEN
  nb := 0;
END_IF;
vlo := 1;
vhi := 16;
nv := vhi - vlo + 1;
IF nv < 0 THEN
  nv := 0;
END_IF;
slo := LOWER_BOUND(Sources, 1);
shi := UPPER_BOUND(Sources, 1);
newScan := NOT started OR tCur <> tLast;
tLast := tCur;
clk := Clock;                    (* no real-time clock on the board: unwired = no clock, never CURRENT_DT *)
IF newScan THEN
  kp();
  IF kp.RestoreSet THEN
    Data.set := keptSet;
  END_IF;
  setOk := Data.set.saveEvery >= T#0s;
  IF NOT setOk AND keptGood AND NOT kp.FirstBoot THEN
    Data.sts.refused := UT_F_SETTING;
    Data.sts.refusedWhy := UT_F_SETTING;
    Data.set := keptSet;
    setOk := TRUE;
  END_IF;
  IF kp.SaveSet AND (setOk OR NOT keptGood) THEN
    keptSet := Data.set;
    keptGood := setOk;
  END_IF;
END_IF;
keep := Data.set.retained AND Data.set.saveEvery > T#0s;
Data.sts.wrnConfig := nb < 1 OR Data.set.saveEvery < T#0s OR (keep AND nb > 16);

IF NOT started THEN
  (* first call, also after a power cut: the kept log (if any), no source seen *)
  started := TRUE;
  quiet := TRUE;
  cnt := 0;
  seqNext := 1;
  FOR i := blo TO bhi DO
    Buffer[i].seq := 0;
    Buffer[i].stamp := DT#1970-01-01-00:00:00;
    Buffer[i].src := 0;
    Buffer[i].code := 0;
    Buffer[i].stop := UT_STOP_NONE;
    Buffer[i].fault := UT_F_NONE;
  END_FOR;
  IF keep THEN
    FOR i := 0 TO MIN(nb, nv) - 1 DO
      IF saved[vlo + i].seq = 0 THEN
        EXIT;                    (* the end of the kept log *)
      END_IF;
      Buffer[blo + i] := saved[vlo + i];
      cnt := cnt + 1;
    END_FOR;
    IF cnt > 0 THEN
      seqNext := Buffer[blo].seq + 1;
    END_IF;
  END_IF;
  FOR i := slo TO shi DO
    Sources[i].seen := FALSE;
  END_FOR;
  IF Data.set.logPowerUp AND nb >= 1 THEN
    take := TRUE;                (* logged below, as source 0 *)
    puOnly := TRUE;
    evSrc := 0;
    evCode := 0;
    evStop := UT_STOP_NONE;
    evFault := UT_F_NONE;
  END_IF;
END_IF;

(* once per scan: the scan's flags and the HMI command (once per request) *)
IF newScan THEN
  NewEvent := FALSE;
  Data.sts.wrnSrc := FALSE;
  IF Data.cmdClear AND NOT clearSeen THEN
    cnt := 0;
    FOR i := blo TO bhi DO
      Buffer[i].seq := 0;
      Buffer[i].stamp := DT#1970-01-01-00:00:00;
      Buffer[i].src := 0;
      Buffer[i].code := 0;
      Buffer[i].stop := UT_STOP_NONE;
      Buffer[i].fault := UT_F_NONE;
    END_FOR;
    dirty := TRUE;
    puOnly := FALSE;
    quiet := TRUE;               (* a clear is saved at once *)
  END_IF;
  clearSeen := Data.cmdClear;
  Data.cmdClear := FALSE;
END_IF;

(* the power-up event, then this call's source *)
FOR m := 0 TO 1 DO
  IF m = 1 THEN
    take := FALSE;
    IF Src < slo OR Src > shi THEN
      Data.sts.wrnSrc := TRUE;
    ELSE
      IF NOT Sources[Src].seen THEN
        take := FALSE;           (* the first call after a power-up: the starting point, not an event *)
        Sources[Src].seen := TRUE;
      ELSE
        take := (New AND NOT Sources[Src].newPrev) OR (Code <> Sources[Src].code AND Code <> 0)
                OR (Stop <> Sources[Src].stop AND Stop <> UT_STOP_NONE)
                OR (Fault <> Sources[Src].fault AND Fault <> UT_F_NONE)
                OR Count <> Sources[Src].count;
      END_IF;
      Sources[Src].code := Code;
      Sources[Src].stop := Stop;
      Sources[Src].fault := Fault;
      Sources[Src].count := Count;
      Sources[Src].newPrev := New;
      IF take THEN
        puOnly := FALSE;
      END_IF;
      evSrc := Src;
      evCode := Code;
      evStop := Stop;
      evFault := Fault;
    END_IF;
  END_IF;
  IF take AND nb >= 1 THEN
    (* newest first: the others move down, the oldest falls off a full log *)
    IF cnt >= nb THEN
      Data.sts.lost := Data.sts.lost + 1;
      cnt := nb - 1;
    END_IF;
    FOR i := bhi TO blo + 1 BY -1 DO
      IF i - blo <= cnt THEN
        Buffer[i] := Buffer[i - 1];
      END_IF;
    END_FOR;
    Buffer[blo].seq := seqNext;
    Buffer[blo].stamp := clk;
    Buffer[blo].src := evSrc;
    Buffer[blo].code := evCode;
    Buffer[blo].stop := evStop;
    Buffer[blo].fault := evFault;
    seqNext := seqNext + 1;
    cnt := cnt + 1;
    Data.sts.logged := Data.sts.logged + 1;
    NewEvent := TRUE;
    dirty := TRUE;
  END_IF;
  take := FALSE;
END_FOR;

(* the kept copy: a change after a quiet spell at once (with the rest of
   that scan), then at most once per saveEvery *)
IF keep THEN
  IF NOT quiet AND tCur - tSave >= Data.set.saveEvery THEN
    quiet := TRUE;
  END_IF;
  IF dirty AND (quiet OR tCur = tSave) THEN
    FOR i := 0 TO nv - 1 DO
      IF i < nb THEN
        saved[vlo + i] := Buffer[blo + i];
      ELSE
        saved[vlo + i].seq := 0;
      END_IF;
    END_FOR;
    dirty := FALSE;
    IF quiet AND NOT puOnly THEN
      quiet := FALSE;            (* the wait starts *)
      tSave := tCur;
    END_IF;
  END_IF;
  puOnly := FALSE;
ELSE
  dirty := FALSE;
  puOnly := FALSE;
END_IF;

Data.sts.count := DINT_TO_INT(cnt);
Events := Data.sts.count;
IF nb >= 1 THEN
  Data.sts.last := Buffer[blo];
END_IF;
BadSetting := NOT setOk OR Data.sts.wrnConfig;
IF BadSetting THEN
  Data.sts.statusCode := UT_ST_WARN_SETTING;
  Data.sts.faultId := UT_F_SETTING;
ELSE
  Data.sts.statusCode := UT_ST_OK;
  Data.sts.faultId := UT_F_NONE;
END_IF;

(* the calls share this instance: an input a call leaves unwired keeps the
   last call's value, so each goes back to its default for the next call *)
Code := 0;
Stop := UT_STOP_NONE;
Fault := UT_F_NONE;
New := FALSE;
Count := 0;
Src := 1;
Clock := DT#1970-01-01-00:00:00;

END_FUNCTION_BLOCK
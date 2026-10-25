(* UT_START_LIMIT — starts per hour (anti-cycling), minimum gap between starts,
wait after a failed start. Private shared piece (UT_PUMP, UT_STARTS).

Every rising edge of Running is a start. The exact start times of the window
are kept over a power cut (decision 52), as whole seconds of the block's own
clock, which only runs while the PLC runs: time with the power off does not
age the window (the safe side). Retained data changes only on a start and,
while a start is still in the window, once a minute (the clock's minutes);
an idle block changes nothing retained, so it causes no saves. After a power
cut the window resumes from the last minute kept, or the newest start if
later: at most a minute of aging is lost (the safe side). Permit is FALSE while maxPerHour starts lie
in the window, before minBetween has passed since the last start, or before
failWait has passed since a failed start; a running motor is never stopped
by it (Permit stays TRUE while Running). Reset clears the waits, not the
counts. maxPerHour 0 = no limit. *)

FUNCTION_BLOCK UT_START_LIMIT
  VAR_INPUT
    Running : BOOL;
    Failed : BOOL; (* a start attempt failed (rising edge) *)
    Reset : BOOL; (* clear the waits (rising edge) *)
  END_VAR
  VAR_OUTPUT
    Permit : BOOL;
    PermitIn : TIME; (* time until a start is permitted *)
    InWindow : INT; (* starts in the window *)
    StartsLeft : INT; (* starts left in the window (-1: no limit) *)
    CfgFault : BOOL; (* a setting is unusable: no start permitted *)
  END_VAR
  VAR_IN_OUT
    Set : UT_START_LIMIT_SET;
  END_VAR
  VAR RETAIN
    clockM : UDINT; (* the block's own minutes, kept only while a start is in the window *)
    stamps : ARRAY [0..29] OF UDINT; (* start times (clockS), newest first *)
    count : INT;
  END_VAR
  VAR NON_RETAIN
    clockS : UDINT; (* the block's own seconds, running only while the PLC runs *)
    inPrev : BOOL; (* a start was in the window last scan *)
    started : BOOL;
    tPrev : TIME;
    rest : TIME;
    runPrev : BOOL;
    failPrev : BOOL;
    resetPrev : BOOL;
    failAt : TIME;
    failing : BOOL;
    lastStartAt : TIME;
    haveStart : BOOL;
  END_VAR
  VAR
    now : TIME;
    k : INT;
    winS : UDINT;
    leftS : UDINT;
    oldest : INT;
    wait : TIME;
    n : INT;
  END_VAR


now := TIME();
IF NOT started THEN
  started := TRUE;
  (* the clock resumes from what was kept: the last minute, or the newest start if later *)
  clockS := clockM * 60;
  IF count > 0 AND stamps[0] > clockS THEN clockS := stamps[0]; END_IF;
  inPrev := FALSE;
  tPrev := now;
  runPrev := Running;          (* already running at power-up: not a new start *)
  failPrev := Failed;
  resetPrev := Reset;
END_IF;
(* the block's clock *)
rest := rest + (now - tPrev);
tPrev := now;
IF rest >= T#1s THEN
  clockS := clockS + DINT_TO_UDINT(TIME_TO_DINT(rest) / 1000);
  rest := rest - DINT_TO_TIME((TIME_TO_DINT(rest) / 1000) * 1000);
END_IF;

n := Set.maxPerHour;
CfgFault := n < 0 OR n > 30 OR (n > 0 AND Set.window <= T#0s)
            OR Set.minBetween < T#0s OR Set.failWait < T#0s;

IF Running AND NOT runPrev THEN
  (* a start: newest first *)
  FOR k := 29 TO 1 BY -1 DO
    stamps[k] := stamps[k - 1];
  END_FOR;
  stamps[0] := clockS;
  IF count < 30 THEN count := count + 1; END_IF;
  lastStartAt := now;
  haveStart := TRUE;
END_IF;
runPrev := Running;
IF Failed AND NOT failPrev THEN
  failAt := now;
  failing := TRUE;
END_IF;
failPrev := Failed;
IF Reset AND NOT resetPrev THEN
  failing := FALSE;
  haveStart := FALSE;
END_IF;
resetPrev := Reset;

(* starts in the window *)
winS := DINT_TO_UDINT(TIME_TO_DINT(Set.window) / 1000);
InWindow := 0;
oldest := -1;
FOR k := 0 TO 29 DO
  IF k < count AND clockS - stamps[k] < winS THEN
    InWindow := InWindow + 1;
    oldest := k;
  END_IF;
END_FOR;

wait := T#0s;
IF n > 0 AND NOT CfgFault AND InWindow >= n AND oldest >= 0 THEN
  (* the oldest start in the window must age out; the n-th newest decides *)
  leftS := winS - (clockS - stamps[n - 1]);
  wait := DINT_TO_TIME(UDINT_TO_DINT(leftS) * 1000) - rest;
END_IF;
(* keep the clock's minutes only while a start is in the window, and once
   more, rounded up, when the last one leaves it, so it stays out after a power cut *)
IF InWindow > 0 AND clockS / 60 > clockM THEN
  clockM := clockS / 60;
ELSIF InWindow = 0 AND inPrev THEN
  clockM := (clockS + 59) / 60;
END_IF;
inPrev := InWindow > 0;
IF haveStart AND Set.minBetween > T#0s AND now - lastStartAt < Set.minBetween THEN
  IF Set.minBetween - (now - lastStartAt) > wait THEN wait := Set.minBetween - (now - lastStartAt); END_IF;
END_IF;
IF failing THEN
  IF now - failAt < Set.failWait THEN
    IF Set.failWait - (now - failAt) > wait THEN wait := Set.failWait - (now - failAt); END_IF;
  ELSE
    failing := FALSE;
  END_IF;
END_IF;
IF wait < T#0s THEN wait := T#0s; END_IF;
PermitIn := wait;
Permit := Running OR (NOT CfgFault AND wait = T#0s);
IF n > 0 THEN
  StartsLeft := n - InWindow;
  IF StartsLeft < 0 THEN StartsLeft := 0; END_IF;
ELSE
  StartsLeft := -1;
END_IF;

END_FUNCTION_BLOCK
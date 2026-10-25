(* UT_GROUP_RUN — which members of a group run: ranking, rotation, staging,
failover, swap, exercise. The one group engine of UT_DUTY, UT_PUMP_STATION
and UT_PUMP_CASCADE (decision 6); each keeps its own process on top (levels,
PV staging, jockey) and sets Required.

The owner fills Members each scan from its members (bit k = member k + 1:
fitted, available, waiting, running, inHand, startsHeld, exercising,
preferLead, and their run hours), calls the piece, then passes each `call`
bit to its member (its group run / Request). Up to 32 members.

Rules (one each, decision 6 table):
- preferLead members (e.g. the VSD) are called first and released last;
- rotation (Set.rotation): FIXED (fixedLead), EACH_START (the lead moves on
  at each group start), HOURS (the fewest kept run hours first, decision 27),
  INTERVAL (every rotateInterval); Rotate (rising edge) rotates now;
- one member called per stageDelay, one released per destageDelay, the most
  recently called first; maxRunning counts Hand members (0 = no limit);
  handCounts: a member running in Hand counts toward Required;
- failover: a called member that is not running and not waiting for
  failoverDelay is skipped and the next one is called at once; a skip clears
  when the member becomes available again, or nothing is required;
- a member held by its starts-per-hour limit waits: AllHeld, no fault
  (decision 20); NoneAvailable only when none could run at all;
- swapWhileRunning: a rotation while running starts the next member first and
  stops the old one once the new one runs (only if maxRunning allows one more);
- exerciseEvery > 0: an idle, available member is run exerciseTime after that
  long idle (members that exercise themselves leave it off);
- Reset: skipped members may be called again; ExerciseIn: until the next
  exercise run;
- invalid settings: CfgFault, nobody called.
The lead is kept over a power cut (VAR RETAIN), changed only by rotation. *)

FUNCTION_BLOCK UT_GROUP_RUN
  VAR_INPUT
    Enable : BOOL := TRUE; (* FALSE: call nobody (Hand members still counted) *)
    Required : INT; (* members wanted nRun *)
    Rotate : BOOL; (* rising edge: rotate now *)
    Reset : BOOL; (* the owner's reset request: skipped members may be called again *)
  END_VAR
  VAR_OUTPUT
    Running : BOOL;
    RunningCount : INT;
    CalledCount : INT;
    Lead : INT; (* 1-based *)
    Shortfall : BOOL;
    NoneAvailable : BOOL;
    AllHeld : BOOL;
    CfgFault : BOOL;
    FaultId : UT_FAULT;
    RotateIn : TIME;
    ExerciseIn : TIME; (* until the next exercise run (0: off, or one running) *)
  END_VAR
  VAR_IN_OUT
    Set : UT_GROUP_SET;
    Members : UT_GROUP_MASKS;
  END_VAR
  VAR RETAIN
    leadIdx : INT := 1; (* kept: the lead (1-based) *)
  END_VAR
  VAR NON_RETAIN
    started : BOOL;
    rotatePrev : BOOL;
    lastCallAt : TIME;
    lastReleaseAt : TIME;
    everCalled : BOOL;
    replaceNow : BOOL;
    stuckSince : TIME;
    stuck : BOOL;
    rotatedAt : TIME;
    availPrev : DWORD;
    seq : UDINT;
    callSeq : ARRAY [0..31] OF UDINT;
    idleSince : ARRAY [0..31] OF TIME;
    exStart : ARRAY [0..31] OF TIME;
    swapOut : INT; (* 0-based member being swapped out, -1 none *)
  END_VAR
  VAR
    now : TIME;
    n : INT;
    k : INT;
    b : DWORD;
    need : INT;
    handRun : INT;
    nRun : INT;
    called : INT;
    candidate : INT;
    best : INT;
    bestH : REAL;
    victim : INT;
    victimSeq : UDINT;
    canRun : DWORD;
    stuckNow : BOOL;
    rot : BOOL;
    limitOk : BOOL;
    i : INT;
    j : INT;
    healthy : INT;
    held : INT;
    active : INT;
  END_VAR


now := TIME();
n := Members.count;
IF NOT started THEN
  started := TRUE;
  rotatePrev := Rotate;
  rotatedAt := now;
  swapOut := -1;
  FOR k := 0 TO 31 DO idleSince[k] := now; END_FOR;
  availPrev := Members.available;
END_IF;

(* settings *)
CfgFault := NOT UT_GROUP_CHECK(N := n, Set := Set, Id => FaultId);
IF n > 32 THEN n := 32; END_IF;
IF leadIdx < 1 OR leadIdx > n THEN leadIdx := 1; END_IF;
IF Set.rotation = UT_ROT_FIXED AND NOT CfgFault THEN leadIdx := Set.fixedLead; END_IF;

(* skipped clears when a member becomes available again, or nothing is required *)
Members.skipped := Members.skipped AND NOT (Members.available AND NOT availPrev);
availPrev := Members.available;
IF Required <= 0 OR Reset THEN Members.skipped := DWORD#0; END_IF;

(* counts *)
nRun := 0;
handRun := 0;
called := 0;
FOR k := 0 TO 31 DO
  IF k < n THEN
    b := SHL(DWORD#1, k);
    IF (Members.running AND b) <> 0 THEN
      nRun := nRun + 1;
      IF (Members.inHand AND b) <> 0 THEN handRun := handRun + 1; END_IF;
      idleSince[k] := now;
    END_IF;
    (* a called member that can no longer run is let go at once *)
    IF (Members.call AND b) <> 0 AND ((Members.fitted AND b) = 0 OR (Members.available AND b) = 0) THEN
      Members.call := Members.call AND NOT b;
      Members.exercise := Members.exercise AND NOT b;
      replaceNow := TRUE;
    END_IF;
    IF (Members.call AND b) <> 0 THEN called := called + 1; END_IF;
  END_IF;
END_FOR;

IF NOT Enable OR CfgFault THEN
  Members.call := DWORD#0;
  Members.exercise := DWORD#0;
  called := 0;
  swapOut := -1;
END_IF;

need := Required;
IF need < 0 THEN need := 0; END_IF;
IF need > n THEN need := n; END_IF;
IF Set.handCounts THEN need := need - handRun; END_IF;
IF need < 0 THEN need := 0; END_IF;
IF NOT Enable OR CfgFault THEN need := 0; END_IF;

(* rotation *)
rot := Rotate AND NOT rotatePrev;
rotatePrev := Rotate;
RotateIn := T#0s;
IF Set.rotation = UT_ROT_INTERVAL AND NOT CfgFault THEN
  IF now - rotatedAt >= Set.rotateInterval THEN rot := TRUE; END_IF;
  RotateIn := Set.rotateInterval - (now - rotatedAt);
  IF RotateIn < T#0s THEN RotateIn := T#0s; END_IF;
END_IF;
IF rot AND Set.rotation <> UT_ROT_FIXED THEN
  rotatedAt := now;
  leadIdx := leadIdx + 1;
  IF leadIdx > n THEN leadIdx := 1; END_IF;
  (* swap a nRun member for the new leadIdx *)
  IF Set.swapWhileRunning AND called > 0 AND swapOut < 0 THEN
    victim := -1; victimSeq := 0;
    FOR k := 0 TO 31 DO
      IF k < n AND (Members.call AND SHL(DWORD#1, k)) <> 0 AND (Members.preferLead AND SHL(DWORD#1, k)) = 0 THEN
        IF victim < 0 OR callSeq[k] < victimSeq THEN victim := k; victimSeq := callSeq[k]; END_IF;
      END_IF;
    END_FOR;
    swapOut := victim;
  END_IF;
END_IF;

(* who could be called now *)
canRun := DWORD#0;
healthy := 0;
held := 0;
FOR k := 0 TO 31 DO
  IF k < n THEN
    b := SHL(DWORD#1, k);
    IF (Members.fitted AND b) <> 0 AND (Members.available AND b) <> 0 AND (Members.skipped AND b) = 0
       AND (Members.exercising AND b) = 0 AND (Members.inHand AND b) = 0 THEN
      healthy := healthy + 1;
      IF (Members.startsHeld AND b) <> 0 THEN
        held := held + 1;
      ELSIF (Members.call AND b) = 0 THEN
        canRun := canRun OR b;
      END_IF;
    END_IF;
  END_IF;
END_FOR;
active := 0;
FOR k := 0 TO 31 DO
  IF k < n AND ((Members.running OR Members.call) AND SHL(DWORD#1, k)) <> 0 THEN active := active + 1; END_IF;
END_FOR;
limitOk := Set.maxRunning = 0 OR active < Set.maxRunning;

(* failover: a called member not nRun and not waiting *)
stuckNow := FALSE;
FOR k := 0 TO 31 DO
  IF k < n THEN
    b := SHL(DWORD#1, k);
    IF (Members.call AND b) <> 0 AND (Members.running AND b) = 0 AND (Members.waiting AND b) = 0 THEN
      stuckNow := TRUE;
    END_IF;
  END_IF;
END_FOR;
IF stuckNow AND NOT stuck THEN stuckSince := now; END_IF;
stuck := stuckNow;
IF stuck AND now - stuckSince >= Set.failoverDelay THEN
  FOR k := 0 TO 31 DO
    IF k < n THEN
      b := SHL(DWORD#1, k);
      IF (Members.call AND b) <> 0 AND (Members.running AND b) = 0 AND (Members.waiting AND b) = 0 THEN
        Members.call := Members.call AND NOT b;
        Members.exercise := Members.exercise AND NOT b;
        Members.skipped := Members.skipped OR b;
        called := called - 1;
        replaceNow := TRUE;
      END_IF;
    END_IF;
  END_FOR;
  stuck := FALSE;
END_IF;

(* call one more *)
IF (called < need OR swapOut >= 0) AND canRun <> DWORD#0 AND limitOk
   AND (replaceNow OR NOT everCalled OR now - lastCallAt >= Set.stageDelay) THEN
  best := -1;
  (* preferLead first *)
  FOR k := 0 TO 31 DO
    IF best < 0 AND k < n AND (canRun AND Members.preferLead AND SHL(DWORD#1, k)) <> 0 THEN best := k; END_IF;
  END_FOR;
  IF best < 0 THEN
    IF Set.rotation = UT_ROT_HOURS THEN
      bestH := 0.0;
      FOR k := 0 TO 31 DO
        IF k < n AND (canRun AND SHL(DWORD#1, k)) <> 0 THEN
          IF best < 0 OR Members.hours[k] < bestH THEN   (* the fewest hours (the band is for swaps) *)
            best := k; bestH := Members.hours[k];
          END_IF;
        END_IF;
      END_FOR;
    ELSE
      (* round from the lead *)
      FOR i := 0 TO 31 DO
        IF i < n AND best < 0 THEN
          j := (leadIdx - 1 + i) MOD n;
          IF (canRun AND SHL(DWORD#1, j)) <> 0 THEN best := j; END_IF;
        END_IF;
      END_FOR;
    END_IF;
  END_IF;
  IF best >= 0 THEN
    IF called = 0 AND Set.rotation = UT_ROT_EACH_START THEN
      (* the lead moves on at each group start: the next start begins after this one *)
      leadIdx := best + 2;
      IF leadIdx > n THEN leadIdx := 1; END_IF;
    END_IF;
    Members.call := Members.call OR SHL(DWORD#1, best);
    seq := seq + 1;
    callSeq[best] := seq;
    called := called + 1;
    lastCallAt := now;
    everCalled := TRUE;
    replaceNow := FALSE;
  END_IF;
END_IF;

(* a swap: the old one goes once the new one runs *)
IF swapOut >= 0 THEN
  IF called > need AND nRun > handRun THEN
    Members.call := Members.call AND NOT SHL(DWORD#1, swapOut);
    called := called - 1;
    lastReleaseAt := now;
    swapOut := -1;
  ELSIF called <= need AND canRun = DWORD#0 THEN
    swapOut := -1;                 (* nobody to swap in *)
  END_IF;
END_IF;

(* release one: the most recently called, preferLead last *)
IF swapOut < 0 AND called > need AND now - lastReleaseAt >= Set.destageDelay THEN
  victim := -1; victimSeq := 0;
  FOR k := 0 TO 31 DO
    IF k < n AND (Members.call AND SHL(DWORD#1, k)) <> 0 AND (Members.preferLead AND SHL(DWORD#1, k)) = 0
       AND (Members.exercise AND SHL(DWORD#1, k)) = 0 THEN
      IF victim < 0 OR callSeq[k] > victimSeq THEN victim := k; victimSeq := callSeq[k]; END_IF;
    END_IF;
  END_FOR;
  IF victim < 0 THEN
    FOR k := 0 TO 31 DO
      IF k < n AND (Members.call AND SHL(DWORD#1, k)) <> 0 AND (Members.exercise AND SHL(DWORD#1, k)) = 0 THEN
        IF victim < 0 OR callSeq[k] > victimSeq THEN victim := k; victimSeq := callSeq[k]; END_IF;
      END_IF;
    END_FOR;
  END_IF;
  IF victim >= 0 THEN
    Members.call := Members.call AND NOT SHL(DWORD#1, victim);
    called := called - 1;
    lastReleaseAt := now;
  END_IF;
END_IF;

(* exercise idle members *)
ExerciseIn := T#0s;
IF Set.exerciseEvery > T#0s AND Enable AND NOT CfgFault THEN
  ExerciseIn := Set.exerciseEvery;
  FOR k := 0 TO 31 DO
    IF k < n THEN
      b := SHL(DWORD#1, k);
      IF (Members.exercise AND b) <> 0 THEN
        IF now - exStart[k] >= Set.exerciseTime THEN
          Members.exercise := Members.exercise AND NOT b;
          Members.call := Members.call AND NOT b;
          idleSince[k] := now;
        END_IF;
      ELSIF (Members.call AND b) = 0 AND (Members.running AND b) = 0 AND (canRun AND b) <> 0
            AND now - idleSince[k] >= Set.exerciseEvery AND need = 0 THEN
        Members.exercise := Members.exercise OR b;
        Members.call := Members.call OR b;
        exStart[k] := now;
      ELSIF (Members.call AND b) = 0 AND (Members.running AND b) = 0 AND (canRun AND b) <> 0
            AND Set.exerciseEvery - (now - idleSince[k]) < ExerciseIn THEN
        ExerciseIn := Set.exerciseEvery - (now - idleSince[k]);
      END_IF;
    END_IF;
  END_FOR;
END_IF;

IF Members.exercise <> DWORD#0 OR ExerciseIn < T#0s THEN
  ExerciseIn := T#0s;
END_IF;

(* outputs *)
CalledCount := 0;
FOR k := 0 TO 31 DO
  IF k < n AND (Members.call AND SHL(DWORD#1, k)) <> 0 THEN CalledCount := CalledCount + 1; END_IF;
END_FOR;
RunningCount := nRun;
Running := nRun > 0;
Lead := leadIdx;
AllHeld := need > 0 AND healthy > 0 AND held = healthy AND CalledCount = 0;
NoneAvailable := need > 0 AND healthy = 0 AND NOT CfgFault;
Shortfall := need > 0 AND (CalledCount < need) AND canRun = DWORD#0;

END_FUNCTION_BLOCK
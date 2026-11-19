(* FB_Group — duty / standby / assist over up to four pumps or motors. It offers I_Equipment itself, so a level
control or a run drives a group as it drives one pump.

Pins: ipMember1..ipMember4 (the members, any I_Equipment: pumps, motors; unwired = none), nExtraMembers (members wanted
beyond the first while it is asked to run: assist / staging; -1 = the jockey alone), bRotate (rising edge: the
lead moves on now), refData -> bAnyMemberRunning, nMembersRunning, nDutyMembers (duty members fitted), nDutyMembersRunning, fRunningCapacity (the running
duty members' I_Pump.fActCapacity summed; 0 = not known), fJockeyCapacity, bJockeyReady, plus FB_Object's outputs.
A member whose I_Pump role is Booster is left out (FB_Booster runs it).
Jockey: the first member that is an I_Pump with role Jockey is not a duty member (never the lead, never staged,
swapped or counted in nDutyMembers). With nExtraMembers -1 (FB_Cascade's low demand), or no duty member available, the group
runs the jockey alone; with nExtraMembers 0 or more it calls the duty members and keeps the jockey on until one of them
runs (the hand-over). A staged stop releases it last.
Parts: a part added to the group (e.g. FB_LevelCheck High on the header flow meter for a burst main) is
evaluated every scan: a trip or a stop releases every member at once (bError and the part's eErrorId on a trip,
stop reason Part), a hold lets none start, a warning shows.
Asked to run: the lead first, then the next available members in rotation order up to 1 + nExtraMembers, one per
set.tAddMemberAfter after the last add or drop; while still asked for fewer, released one per set.tDropMemberAfter
(after the last add or drop), the most recent first. Failover: a called member that is
not running after set.tFailoverAfter is skipped and the next one is called at once (until a reset or nothing is
asked); a member that became unavailable is skipped until it is available again. Rotation (set.eRotateBy): EachStart (the lead moves on at
each group start), Periodic (every set.tRotateInterval), Fixed (set.nFixedLeadMember). The lead is kept over a power
cut. Nobody available while asked: a warning (NoneAvailable).
Hours rotation (set.eRotateBy = Hours): each call takes the available member with the fewest run hours (each
member's fActRunHours, e.g. FB_Pump / FB_Motor's tot.fRunHours); members within set.fEqualHoursBand hours of each
other count as equal and go in rotation order, and the lead moves on at each group start, so equal members
take turns.
A member in Hand is never called (it is not available); while it runs it counts toward the members wanted
(set.bHandRunCounts, default on) and always toward set.nMaxMembersRunning, the most members running at once (0 = no
limit).
Swap while running (set.bSwapWhileRunning): a rotation while the group runs (bRotate, bCmdRotateNow, Periodic)
calls the next member first and releases the longest-running one (not the new lead) once the new one runs;
nobody available, or no room under nMaxMembersRunning: no swap.
Stop (set.eStopOrder): when nothing is asked any more, AllAtOnce releases every member; Staged releases the most
recent first: the first at once, then one per set.tStagedStopInterval (a shutdown gap, not the tDropMemberAfter of a
smaller request). A new request during a staged stop keeps those still running.
Exercise (set.tExerciseAfterIdle, 0 = off): while nothing is asked, a member that has not run for tExerciseAfterIdle
(an available one, not skipped) runs for set.tExerciseRunTime; a request, the member going unavailable or the
setting off ends it; sts.nMembersExercising, sts.tNextExerciseTimeLeft (until the next one). Idle time counts power-on time only
(no clock). A member that exercises itself, or an owner exercise (FB_Exercise on the level control: it asks the
group, so the lead runs), leaves this off.
Status: sts.nMembersAvailable (duty members available), sts.bMembersShort (asked for more members than can run: none left to
call, or nMaxMembersRunning reached), sts.tRotateTimeLeft (Periodic: until the next rotation), sts.bStopping (a staged stop).
An invalid setting is refused and put back (sts.bSettingRefused / eSettingRefusedErrorId, a warning until a reset). *)

FUNCTION_BLOCK FB_Group EXTENDS FB_Object IMPLEMENTS I_Equipment
  VAR_INPUT
    ipMember1 : I_Equipment; (* member 1 (a pump, motor or valve; unwired = none) *)
    ipMember2 : I_Equipment; (* member 2 (unwired = none) *)
    ipMember3 : I_Equipment; (* member 3 (unwired = none) *)
    ipMember4 : I_Equipment; (* member 4 (unwired = none) *)
    nExtraMembers : INT; (* members wanted beyond the first while it is asked to run; -1 = the jockey alone *)
    bRotate : BOOL R_EDGE; (* rising edge: the lead moves on now *)
    refData : REFERENCE TO ST_GroupData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bAnyMemberRunning : BOOL; (* a member runs *)
    nDutyMembers : INT; (* duty members fitted (the jockey not counted): -> FB_Cascade.nDutyPumps *)
    nDutyMembersRunning : INT; (* duty members running: -> FB_Cascade.nDutyPumpsRunning *)
    fRunningCapacity : REAL; (* the running duty members' capacity (I_Pump.fActCapacity; 0 = not known) *)
    fJockeyCapacity : REAL; (* the jockey's capacity (0 = none, or not known) *)
    bJockeyReady : BOOL; (* a jockey is fitted and available *)
    nMembersRunning : INT; (* members running now *)
  END_VAR
  VAR RETAIN
    stKept : ST_GroupSet;
    nKeptLayout : UINT;
    nLead : INT := 1; (* kept over a power cut *)
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
    cMax : INT := 4;
  END_VAR
  VAR
    bAnyAvail : BOOL; (* a member was available on the last scan *)
    aMembers : ARRAY [1..4] OF I_EQUIPMENT;
    aCalled : ARRAY [1..4] OF BOOL;
    aSkipped : ARRAY [1..4] OF BOOL;
    aSkipUnavail : ARRAY [1..4] OF BOOL; (* skipped because it was unavailable (clears when available again) *)
    aCalledAt : ARRAY [1..4] OF TIME;
    aOrder : ARRAY [1..4] OF INT; (* the order of the last calls (1 = first called) *)
    bReq : BOOL;
    bReqSeen : BOOL;
    bReqPrev : BOOL;
    fSpeedReq : REAL := -1.0;
    bUrgentReq : BOOL;
    tLastStage : TIME;
    tRotatedAt : TIME;
    nSeq : INT;
    eStop : E_StopReason;
    nSwapOut : INT; (* the member a swap stops once the new one runs (0 = none) *)
    nSwapIn : INT; (* the member a swap started (0 = not yet) *)
    tLastStop : TIME;
    bStopping : BOOL; (* Staged stop under way *)
    aIdleSince : ARRAY [1..4] OF TIME;
    aExercise : ARRAY [1..4] OF BOOL;
    aExStart : ARRAY [1..4] OF TIME;
  END_VAR
  VAR_TEMP
    nI : INT;
    nK : INT;
    nM : INT;
    nCalled : INT;
    nRequired : INT;
    nAvail : INT;
    nLast : INT;
    bX : BOOL;
    nLastSeq : INT;
    bReset : BOOL;
    nHandRun : INT;
    nActive : INT;
    bLimitOk : BOOL;
    bRotateNow : BOOL;
    nBest : INT;
    fBestHours : REAL;
    fHours : REAL;
    nExercising : INT;
    tExIn : TIME;
    nJockey : INT; (* the jockey member (0 = none) *)
    nDutyRun : INT;
    bJockeyTurn : BOOL;
    bPartOff : BOOL;
    ipM : I_Equipment;
    ipP : I_Pump;
    fCap : REAL;
  END_VAR


(* the first bad setting (None: all good) *)
METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.tAddMemberAfter >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tDropMemberAfter >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tFailoverAfter >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tRotateInterval >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.nFixedLeadMember >= 1) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.nFixedLeadMember <= cMax) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.nMaxMembersRunning >= 0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.nMaxMembersRunning <= cMax) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.tStagedStopInterval >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.fEqualHoursBand >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.tExerciseAfterIdle >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tExerciseRunTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.eStopOrder = E_GroupStop.AllAtOnce OR refData.set.eStopOrder = E_GroupStop.Staged) THEN
    SetWhy := E_UtError.ChoiceBad;
  END_IF;
END_METHOD

(* ---- I_Equipment ---- *)
METHOD PUBLIC Request : E_UtError
  VAR_INPUT
    bRun : BOOL;    // run wanted
    bHoldOff : BOOL;    // held off, still linked to the owner
    fSpeedSetpointPct : REAL := -1.0;    // speed wanted; below 0 = each member's own
    bOverflowUrgent : BOOL;    // an overflow call: a part's start hold does not hold it
  END_VAR
  bReq := bRun AND NOT bHoldOff;
  bUrgentReq := bOverflowUrgent;
  fSpeedReq := fSpeedSetpointPct;
  bReqSeen := TRUE;
  Request := eErrorId;
END_METHOD

METHOD PUBLIC Command
  VAR_INPUT
    eCommand : E_EquipCmd;    // a record command applied in the block's next cycle
  END_VAR
  IF eCommand = E_EquipCmd.Reset AND __ISVALIDREF(refData) THEN
    refData.bCmdResetFaults := TRUE;
  END_IF;
END_METHOD

PROPERTY PUBLIC eActMode : E_Mode    // the mode it is in now
  GET
    eActMode := E_Mode.Auto;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsRunning : BOOL    // a member is running
  GET
    bIsRunning := bAnyMemberRunning;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsReady : BOOL    // could start now if asked
  GET
    bIsReady := NOT bWarning OR bAnyMemberRunning;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsAvailable : BOOL    // in Auto, not tripped, not interlocked
  GET
    bIsAvailable := (bAnyAvail AND NOT bError) OR bAnyMemberRunning;   // a member can run (a warning is not "unavailable")
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsAuto : BOOL    // in Auto now
  GET
    bIsAuto := TRUE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsFaulted : BOOL    // a trip or setting fault is active
  GET
    bIsFaulted := bError;
  END_GET
END_PROPERTY
PROPERTY PUBLIC eActError : E_UtError    // the error shown now
  GET
    eActError := eErrorId;
  END_GET
END_PROPERTY
PROPERTY PUBLIC eActStopReason : E_StopReason    // why it last stopped
  GET
    eActStopReason := eStop;
  END_GET
END_PROPERTY

PROPERTY PUBLIC fActRunHours : REAL   // a group counts no hours of its own
  GET
    fActRunHours := 0.0;
  END_GET
END_PROPERTY

(* the member k places after the lead *)
METHOD PRIVATE Nth : INT
  VAR_INPUT
    nK : INT;
  END_VAR
  Nth := ((nLead - 1 + nK) MOD cMax) + 1;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  RETURN;
END_IF;
tNow := TIME();
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
  tRotatedAt := tNow;
  IF nLead < 1 OR nLead > cMax THEN nLead := 1; END_IF;
  FOR nI := 1 TO cMax DO aIdleSince[nI] := tNow; END_FOR;
ELSIF SetWhy() = E_UtError.None THEN
  stKept := refData.set;
ELSE
  refData.sts.eSettingRefusedErrorId := SetWhy();
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;
aMembers[1] := ipMember1;
aMembers[2] := ipMember2;
aMembers[3] := ipMember3;
aMembers[4] := ipMember4;
(* roles: the first member whose I_Pump role is Jockey is the jockey (a second one is a duty pump) *)
nJockey := 0;
nDutyMembers := 0;
fJockeyCapacity := 0.0;
FOR nI := 1 TO cMax DO
  ipM := aMembers[nI];
  IF ipM <> NULL THEN
    IF __QUERYINTERFACE(ipM, ipP) THEN
      IF ipP.eActRole = E_PumpRole.Booster THEN
        aMembers[nI] := NULL;     (* a booster is never a group member: FB_Booster runs it *)
      ELSIF ipP.eActRole = E_PumpRole.Jockey AND nJockey = 0 THEN
        nJockey := nI;
        fJockeyCapacity := MAX(0.0, ipP.fActCapacity);
      END_IF;
    END_IF;
    IF nJockey <> nI AND aMembers[nI] <> NULL THEN nDutyMembers := nDutyMembers + 1; END_IF;
  END_IF;
END_FOR;

(* the owner's request: every scan, else gone *)
IF NOT bReqSeen THEN
  bReq := FALSE;
  bUrgentReq := FALSE;
END_IF;
bReqSeen := FALSE;
bReset := refData.bCmdResetFaults OR SystemReset();
IF refData.bCmdResetFaults THEN
  refData.bCmdResetFaults := FALSE;
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

(* rotation *)
IF refData.set.eRotateBy = E_Rotate.Fixed THEN
  nLead := refData.set.nFixedLeadMember;
ELSE
  bRotateNow := bRotate OR refData.bCmdRotateNow
      OR ((refData.set.eRotateBy = E_Rotate.EachStart OR refData.set.eRotateBy = E_Rotate.Hours) AND bReq AND NOT bReqPrev)
      OR (refData.set.eRotateBy = E_Rotate.Periodic AND refData.set.tRotateInterval > T#0s
          AND tNow - tRotatedAt >= refData.set.tRotateInterval);
  IF bRotateNow THEN
    FOR nK := 1 TO cMax DO         // the next fitted member
      nLead := (nLead MOD cMax) + 1;
      IF aMembers[nLead] <> NULL AND nLead <> nJockey THEN EXIT; END_IF;
    END_FOR;
    tRotatedAt := tNow;
    (* swap while running: the oldest called member goes once the next one runs *)
    IF refData.set.bSwapWhileRunning AND nSwapOut = 0 AND bReq THEN
      nLastSeq := 0;
      FOR nI := 1 TO cMax DO
        IF aCalled[nI] AND nI <> nLead AND nI <> nJockey AND (nSwapOut = 0 OR aOrder[nI] < nLastSeq) THEN
          nSwapOut := nI;
          nLastSeq := aOrder[nI];
        END_IF;
      END_FOR;
      nSwapIn := 0;
    END_IF;
  END_IF;
END_IF;
refData.bCmdRotateNow := FALSE;
bReqPrev := bReq;

(* skips: cleared when available again, on a reset, or when nothing is asked *)
nCalled := 0;
nAvail := 0;
nHandRun := 0;
nActive := 0;
nDutyRun := 0;
fRunningCapacity := 0.0;
FOR nI := 1 TO cMax DO
  IF aMembers[nI] = NULL THEN
    aCalled[nI] := FALSE;
    aSkipped[nI] := FALSE;
    aExercise[nI] := FALSE;
    aIdleSince[nI] := tNow;
  ELSE
    IF aMembers[nI].bIsRunning AND NOT aExercise[nI] THEN aIdleSince[nI] := tNow; END_IF;
    (* a skip clears on a reset or when nothing is asked; a skip for being unavailable also when it is
       available again (a failover skip stays: the member is available but did not run) *)
    IF aSkipped[nI] AND (bReset OR NOT bReq OR (aSkipUnavail[nI] AND aMembers[nI].bIsAvailable)) THEN
      aSkipped[nI] := FALSE;
      aSkipUnavail[nI] := FALSE;
    END_IF;
    IF aCalled[nI] AND NOT aMembers[nI].bIsRunning AND tNow - aCalledAt[nI] >= refData.set.tFailoverAfter THEN
      aSkipped[nI] := TRUE;        // failover: called, not running in time
      aSkipUnavail[nI] := FALSE;
      aCalled[nI] := FALSE;
    END_IF;
    IF aCalled[nI] AND NOT aMembers[nI].bIsAvailable AND NOT aMembers[nI].bIsRunning THEN
      aCalled[nI] := FALSE;        // it became unavailable: call the next at once
      aSkipped[nI] := TRUE;
      aSkipUnavail[nI] := TRUE;
    END_IF;
    IF nI <> nJockey THEN
      IF aCalled[nI] THEN nCalled := nCalled + 1; END_IF;
      IF aMembers[nI].bIsAvailable AND NOT aSkipped[nI] THEN nAvail := nAvail + 1; END_IF;
      IF aMembers[nI].bIsRunning THEN
        nDutyRun := nDutyRun + 1;
        ipM := aMembers[nI];
        IF __QUERYINTERFACE(ipM, ipP) THEN fCap := ipP.fActCapacity; ELSE fCap := 0.0; END_IF;
        IF fCap > 0.0 THEN fRunningCapacity := fRunningCapacity + fCap; END_IF;
      END_IF;
    END_IF;
    IF aMembers[nI].bIsRunning AND aMembers[nI].eActMode = E_Mode.Hand THEN nHandRun := nHandRun + 1; END_IF;
    IF aCalled[nI] OR aMembers[nI].bIsRunning THEN nActive := nActive + 1; END_IF;
  END_IF;
END_FOR;

bJockeyReady := FALSE;
IF nJockey > 0 THEN
  bJockeyReady := aMembers[nJockey].bIsAvailable AND NOT aSkipped[nJockey];
END_IF;
bJockeyTurn := bReq AND bJockeyReady AND (nExtraMembers < 0 OR (nAvail = 0 AND nCalled = 0));   // no duty: the jockey
IF bJockeyTurn THEN
  nRequired := 0;                  // the jockey alone
ELSIF bReq THEN
  nRequired := MIN(cMax, 1 + MAX(0, nExtraMembers));
  IF refData.set.bHandRunCounts THEN nRequired := MAX(0, nRequired - nHandRun); END_IF;
ELSE
  nRequired := 0;
END_IF;
bLimitOk := refData.set.nMaxMembersRunning = 0 OR nActive < refData.set.nMaxMembersRunning;
(* the group's parts (e.g. FB_LevelCheck on the header flow: a burst main): a trip or a stop releases every
   member at once, a hold lets none start *)
EvaluateParts(bRunning := bAnyMemberRunning, bResetWanted := bReset, bMasked := FALSE);
bPartOff := bPartTrip OR bPartStop;
IF bPartOff THEN
  nRequired := 0;
  bJockeyTurn := FALSE;
  FOR nI := 1 TO cMax DO aCalled[nI] := FALSE; END_FOR;
  nCalled := 0;
  nSwapOut := 0;
END_IF;
IF bPartHold THEN bLimitOk := FALSE; END_IF;
IF nSwapOut > 0 THEN                 // IEC AND does not short-circuit: test the index on its own
  IF NOT aCalled[nSwapOut] THEN
    nSwapOut := 0;                 // the old one went (failover, unavailable, released): no swap left
  END_IF;
END_IF;

(* call one more: at once for the first or after a failover, else one per stage delay; a swap calls the
   next member too, if nMaxMembersRunning allows one more *)
IF (nCalled < nRequired OR (nSwapOut > 0 AND nSwapIn = 0)) AND bLimitOk
   AND (nCalled = 0 OR tNow - tLastStage >= refData.set.tAddMemberAfter) THEN
  (* rotation order from the lead; Hours: the fewest run hours, closer than fEqualHoursBand counts as equal *)
  nBest := 0;
  fBestHours := 0.0;
  FOR nK := 0 TO cMax - 1 DO
    nM := Nth(nK := nK);
    IF aMembers[nM] <> NULL THEN       // IEC AND does not short-circuit: test NULL on its own
      IF NOT aCalled[nM] AND NOT aSkipped[nM] AND aMembers[nM].bIsAvailable AND nM <> nJockey THEN
        fHours := aMembers[nM].fActRunHours;
        IF nBest = 0 OR (refData.set.eRotateBy = E_Rotate.Hours AND fHours < fBestHours - refData.set.fEqualHoursBand) THEN
          nBest := nM;
          fBestHours := fHours;
        END_IF;
      END_IF;
    END_IF;
  END_FOR;
  IF nBest > 0 THEN
    IF refData.set.eRotateBy = E_Rotate.Hours AND nCalled = 0 THEN
      nLead := nBest;              // the first called leads: the next start goes on from it
    END_IF;
    aCalled[nBest] := TRUE;
    aCalledAt[nBest] := tNow;
    nSeq := nSeq + 1;
    aOrder[nBest] := nSeq;
    tLastStage := tNow;
    nCalled := nCalled + 1;
    IF nSwapOut > 0 AND nSwapIn = 0 THEN nSwapIn := nBest; END_IF;
  END_IF;
END_IF;
(* a swap: the old one goes once the new one runs; nobody to swap in, or no room: no swap *)
IF nSwapOut > 0 THEN
  IF nSwapIn > 0 THEN
    IF aMembers[nSwapIn] <> NULL THEN
      IF aMembers[nSwapIn].bIsRunning THEN
        aCalled[nSwapOut] := FALSE;
        nCalled := nCalled - 1;
        tLastStage := tNow;
        nSwapOut := 0;
        nSwapIn := 0;
      ELSIF NOT aCalled[nSwapIn] THEN
        nSwapIn := 0;              // the new one dropped out (failover): try the next
      END_IF;
    END_IF;
  ELSIF NOT bLimitOk OR nAvail <= nCalled THEN
    nSwapOut := 0;
  END_IF;
END_IF;

(* release one: when nothing is asked all at once (or Staged: the most recent first, one per tBetweenMemberStops), else
   the most recent one per destage delay *)
IF bReq OR nCalled = 0 THEN
  bStopping := FALSE;
END_IF;
IF NOT bReq AND refData.set.eStopOrder = E_GroupStop.AllAtOnce THEN
  FOR nI := 1 TO cMax DO aCalled[nI] := FALSE; END_FOR;
  nCalled := 0;
  nSwapOut := 0;
ELSIF NOT bReq THEN
  bX := FALSE;
  IF nJockey > 0 THEN bX := aCalled[nJockey]; END_IF;
  IF (nCalled > 0 OR bX) AND (NOT bStopping OR tNow - tLastStop >= refData.set.tStagedStopInterval) THEN
    nLast := 0;
    nLastSeq := -1;
    FOR nI := 1 TO cMax DO
      IF aCalled[nI] AND nI <> nJockey AND aOrder[nI] > nLastSeq THEN nLast := nI; nLastSeq := aOrder[nI]; END_IF;
    END_FOR;
    IF nLast > 0 THEN
      aCalled[nLast] := FALSE;
      nCalled := nCalled - 1;
    ELSIF bX THEN
      aCalled[nJockey] := FALSE;   // the jockey goes last
    END_IF;
    tLastStop := tNow;
    bStopping := TRUE;
  END_IF;
  nSwapOut := 0;
ELSIF nSwapOut = 0 AND nCalled > nRequired AND tNow - tLastStage >= refData.set.tDropMemberAfter THEN
  nLast := 0;
  nLastSeq := -1;
  FOR nI := 1 TO cMax DO
    IF aCalled[nI] AND nI <> nJockey AND aOrder[nI] > nLastSeq THEN nLast := nI; nLastSeq := aOrder[nI]; END_IF;
  END_FOR;
  IF nLast > 0 THEN
    aCalled[nLast] := FALSE;
    tLastStage := tNow;
    nCalled := nCalled - 1;
  END_IF;
END_IF;

(* the jockey: called on its turn; once a duty member runs it is released (the hand-over) *)
IF nJockey > 0 AND bReq AND NOT bPartOff THEN
  IF bJockeyTurn THEN
    IF NOT aCalled[nJockey] AND (bLimitOk OR aMembers[nJockey].bIsRunning) THEN
      aCalled[nJockey] := TRUE;
      aCalledAt[nJockey] := tNow;
      nSeq := nSeq + 1;
      aOrder[nJockey] := nSeq;
    END_IF;
  ELSIF aCalled[nJockey] AND nDutyRun > 0 THEN
    aCalled[nJockey] := FALSE;
  END_IF;
END_IF;

(* exercise: while nothing is asked, a member idle for tExerciseAfterIdle runs for tExerciseRunTime (an asked run, a
   member gone unavailable or the setting off ends it) *)
nExercising := 0;
tExIn := T#0s;
IF refData.set.tExerciseAfterIdle > T#0s AND NOT bReq THEN
  tExIn := refData.set.tExerciseAfterIdle;
END_IF;
FOR nI := 1 TO cMax DO
  IF aMembers[nI] = NULL OR bReq OR bPartOff OR refData.set.tExerciseAfterIdle <= T#0s THEN
    IF aExercise[nI] THEN aIdleSince[nI] := tNow; END_IF;
    aExercise[nI] := FALSE;
  ELSIF aExercise[nI] THEN
    IF tNow - aExStart[nI] >= refData.set.tExerciseRunTime OR NOT (aMembers[nI].bIsAvailable OR aMembers[nI].bIsRunning) THEN
      aExercise[nI] := FALSE;
      aIdleSince[nI] := tNow;
    END_IF;
  ELSIF NOT aCalled[nI] AND NOT aMembers[nI].bIsRunning AND aMembers[nI].bIsAvailable AND NOT aSkipped[nI] THEN
    IF tNow - aIdleSince[nI] >= refData.set.tExerciseAfterIdle THEN
      aExercise[nI] := TRUE;
      aExStart[nI] := tNow;
    ELSIF refData.set.tExerciseAfterIdle - (tNow - aIdleSince[nI]) < tExIn THEN
      tExIn := refData.set.tExerciseAfterIdle - (tNow - aIdleSince[nI]);
    END_IF;
  END_IF;
  IF aExercise[nI] THEN nExercising := nExercising + 1; END_IF;
END_FOR;
IF nExercising > 0 THEN tExIn := T#0s; END_IF;

(* drive the members (their owner link: every scan) *)
nMembersRunning := 0;
FOR nI := 1 TO cMax DO
  IF aMembers[nI] <> NULL THEN
    aMembers[nI].Request(bRun := aCalled[nI] OR aExercise[nI], bHoldOff := FALSE, fSpeedSetpointPct := fSpeedReq,
                         bOverflowUrgent := bUrgentReq AND aCalled[nI]);
    IF aMembers[nI].bIsRunning THEN nMembersRunning := nMembersRunning + 1; END_IF;
  END_IF;
END_FOR;
bAnyMemberRunning := nMembersRunning > 0;
bAnyAvail := nAvail > 0;
nDutyMembersRunning := nDutyRun;

(* status *)
bError := bPartTrip;
bWarning := NOT bError AND ((bReq AND nAvail = 0 AND nMembersRunning = 0) OR bPartWarn OR refData.sts.bSettingRefused);
IF bPartTrip THEN
  eErrorId := ePartTrip;
ELSIF bReq AND nAvail = 0 AND nMembersRunning = 0 THEN
  eErrorId := E_UtError.NoneAvailable;
ELSIF bPartWarn THEN
  eErrorId := ePartWarn;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bPartTrip THEN
  eState := E_State.Fault;
ELSIF NOT bReq THEN
  eState := E_State.Idle;
ELSIF nMembersRunning > 0 THEN
  eState := E_State.Running;
ELSIF nAvail = 0 THEN
  eState := E_State.Held;
ELSE
  eState := E_State.Starting;
END_IF;
IF bPartOff AND bAnyMemberRunning THEN
  eStop := E_StopReason.Part;
ELSIF NOT bReq AND bAnyMemberRunning THEN
  eStop := E_StopReason.Request;
END_IF;
refData.sts.eState := eState;
refData.sts.eErrorId := eErrorId;
refData.sts.nLeadMember := nLead;
refData.sts.nMembersRequired := nRequired;
refData.sts.nMembersRunning := nMembersRunning;
refData.sts.nMembersCalled := nCalled;
refData.sts.nMembersExercising := nExercising;
refData.sts.tNextExerciseTimeLeft := tExIn;
refData.sts.nMembersAvailable := nAvail;
refData.sts.bMembersShort := bReq AND NOT bPartOff AND nCalled < nRequired AND (nAvail <= nCalled OR NOT bLimitOk);
IF refData.set.eRotateBy = E_Rotate.Periodic AND refData.set.tRotateInterval > T#0s THEN
  refData.sts.tRotateTimeLeft := MAX(T#0s, refData.set.tRotateInterval - (tNow - tRotatedAt));
ELSE
  refData.sts.tRotateTimeLeft := T#0s;
END_IF;
refData.sts.bStopping := bStopping;
bFirstScan := FALSE;

END_FUNCTION_BLOCK
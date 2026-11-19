(* FB_Interlock — the conditions that must all be healthy before a device may run, as one bPermissive signal (-> the
device's bInterlock or bPermissive), with first-out and maintenance bypasses.
Pins: bBypassKeyOn (key switch / HMI permission for bypasses), bResetFaults (clear the first-out and the held
conditions), refData (set, sts), and the tables the project declares (VAR_IN_OUT, the same size, at most 16 rows):
aConditionSettings (each condition's settings) and aConditions (each condition's live row: the project writes aConditions[i].bPermissive on the
condition's own rung, the HMI aConditions[i].bBypassRequest) -> bPermissive (all healthy or bypassed), nFirstOutCondition (the first condition
to stop the device since the last reset, 1-based; 0 = none), nConditionsNotMet, bBypassInEffect (a bypass in effect: show it),
plus FB_Object's bError / bWarning / eErrorId / eState.
Each condition: tTripDelay (must be not OK this long to count); eResetMode Auto (OK again as soon as healthy), Manual
(held until a reset while healthy: pull cords, e-stops) or Retry (by itself while healthy, at most
set.nMaxRetriesBeforeLockout times in set.tRetryCountWindow, then held); a bypass (its bBypassRequest, only when bBypassAllowed, while
bBypassKeyOn, for at most set.tBypassEndsAfter, 0 = never drops out; once timed out it stays off until the request
or bBypassKeyOn goes). nFirstOutCondition: the condition that went out first (same scan: the lowest); after a reset with
conditions still out, the lowest of those. A reset acts in the same scan.
Errors: bError for no rows, tables of different sizes or more than 16 rows, or settings that were never good
(BadSetting); bWarning for a bypass (Bypassed) or a refused write (SettingRefused). Not OK is the block's job, not
an error: eState Held, eErrorId ConditionOut.
Kept settings (a retained last-good copy, restored at power-up, a bad write put back, sts.bSettingRefused / eSettingRefusedErrorId):
set, and
each condition row packed into one DWORD: bits 0..1 eResetMode, 2 bBypassAllowed, 3..31 tTripDelay in 10 ms steps
(0 .. about 62 days; kept rounded down to 10 ms).
Times: each row shows tTripDelayTimeLeft (not OK, until it counts), tBypassedFor / tBypassTimeLeft (a bypass so far / until it
drops out); sts.tTimeLeft is the shortest delay left. *)

FUNCTION_BLOCK FB_Interlock EXTENDS FB_Object
  VAR_INPUT
    bBypassKeyOn : BOOL := FALSE; (* key switch / HMI permission for bypasses *)
    bResetFaults : BOOL R_EDGE; (* clear the first-out and the held conditions *)
    refData : REFERENCE TO ST_IntlkData; (* the interlock's record *)
  END_VAR
  VAR_IN_OUT
    aConditionSettings : ARRAY [*] OF ST_INTLKCONDSET; (* each condition's settings (same size as aCondition) *)
    aConditions : ARRAY [*] OF ST_INTLKCOND; (* each condition's live row; the project writes aConditions[i].bConditionMet *)
  END_VAR
  VAR_OUTPUT
    bPermissive : BOOL; (* all OK or bypassed -> the device's bInterlock / bPermissive *)
    nFirstOutCondition : INT; (* the first condition out since the reset (1-based; 0 = none) *)
    nConditionsNotMet : INT; (* conditions not OK now *)
    bBypassInEffect : BOOL; (* a bypass in effect (show it!) *)
  END_VAR
  VAR RETAIN
    stKept : ST_IntlkSet;
    aKeptCond : ARRAY [1..16] OF DWORD;
    nKeptRows : INT;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
    cMaxRows : INT := 16;
  END_VAR
  VAR
    bOkPrev : BOOL := TRUE;
    bResetSeen : BOOL;
  END_VAR
  VAR_TEMP
    tLeftMin : TIME;
    bOkSet : BOOL;
    bRowsOk : BOOL;
    bCfgBad : BOOL;
    bResetReq : BOOL;
    bActive : BOOL;
    bBadSet : BOOL;
    nLb : DINT;
    nRows : INT;
    nI : INT;
    nR : DINT;
    nS : DINT;
    nFirst : INT;
    nWentFirst : INT;
    nPacked : DWORD;
  END_VAR


(* the block's settings are usable *)
METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_IntlkSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.tBypassEndsAfter >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.nMaxRetriesBeforeLockout >= 0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_IntlkSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

(* one condition's settings are usable (and fit the kept form) *)
METHOD PRIVATE CondWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_IntlkCondSet;
  END_VAR
  CondWhy := E_UtError.None;
  IF NOT (stS.tTripDelay >= T#0s) THEN
    CondWhy := E_UtError.TimeBad;
  ELSIF NOT (TIME_TO_LINT(stS.tTripDelay) / 10 <= 16#1FFFFFFF) THEN
    CondWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.eResetMode = E_ResetMode.Auto OR stS.eResetMode = E_ResetMode.Retry OR stS.eResetMode = E_ResetMode.Manual) THEN
    CondWhy := E_UtError.ProtectionBad;
  END_IF;
END_METHOD

METHOD PRIVATE CondOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_IntlkCondSet;
  END_VAR
  CondOk := CondWhy(stS := stS) = E_UtError.None;
END_METHOD

(* one condition's settings as its kept DWORD, and back *)
METHOD PRIVATE Pack : DWORD
  VAR_INPUT
    stS : REFERENCE TO ST_IntlkCondSet;
  END_VAR
  Pack := SHL(LINT_TO_DWORD(TIME_TO_LINT(stS.tTripDelay) / 10), 3) OR USINT_TO_DWORD(TO_USINT(stS.eResetMode));
  IF stS.bBypassAllowed THEN
    Pack := Pack OR DWORD#16#4;
  END_IF;
END_METHOD

METHOD PRIVATE Unpack : BOOL
  VAR_INPUT
    nW : DWORD;
    stS : REFERENCE TO ST_IntlkCondSet;
  END_VAR
  stS.tTripDelay := LINT_TO_TIME(DWORD_TO_LINT(SHR(nW, 3)) * 10);
  CASE DWORD_TO_USINT(nW AND DWORD#16#3) OF
    0: stS.eResetMode := E_ResetMode.Manual;
    1: stS.eResetMode := E_ResetMode.Retry;
  ELSE
    stS.eResetMode := E_ResetMode.Auto;
  END_CASE;
  stS.bBypassAllowed := (nW AND DWORD#16#4) <> DWORD#0;
  Unpack := TRUE;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bPermissive := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
nLb := LOWER_BOUND(aConditions, 1);
nRows := DINT_TO_INT(UPPER_BOUND(aConditions, 1) - nLb + 1);
bCfgBad := nRows < 1 OR nRows > cMaxRows
           OR UPPER_BOUND(aConditionSettings, 1) - LOWER_BOUND(aConditionSettings, 1) + 1 <> INT_TO_DINT(nRows);
IF bCfgBad THEN
  nRows := 0;
END_IF;

(* kept settings; a bad write is put back *)
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    FOR nI := 1 TO MIN(nRows, nKeptRows) DO
      nS := LOWER_BOUND(aConditionSettings, 1) + nI - 1;
      Unpack(nW := aKeptCond[nI], stS := aConditionSettings[nS]);
    END_FOR;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
END_IF;
bOkSet := SetOk(stS := refData.set);
IF bOkSet THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
  bOkSet := TRUE;
END_IF;
bRowsOk := TRUE;
FOR nI := 1 TO nRows DO
  nS := LOWER_BOUND(aConditionSettings, 1) + nI - 1;
  IF CondOk(stS := aConditionSettings[nS]) THEN
    aKeptCond[nI] := Pack(stS := aConditionSettings[nS]);
  ELSIF nI <= nKeptRows THEN
    refData.sts.eSettingRefusedErrorId := CondWhy(stS := aConditionSettings[nS]);
    Unpack(nW := aKeptCond[nI], stS := aConditionSettings[nS]);
    refData.sts.bSettingRefused := TRUE;
  ELSE
    bRowsOk := FALSE;             (* never good: no copy to put back *)
  END_IF;
END_FOR;
IF nRows > nKeptRows AND bRowsOk THEN
  nKeptRows := nRows;
END_IF;

(* the reset: the pin, the system, the HMI once per write *)
bResetReq := bResetFaults OR SystemReset() OR (refData.bCmdResetFaults AND NOT bResetSeen);
bResetSeen := refData.bCmdResetFaults;
refData.bCmdResetFaults := FALSE;
IF bResetReq THEN
  nFirstOutCondition := 0;
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

(* each condition *)
bPermissive := nRows > 0;
bBypassInEffect := FALSE;
nConditionsNotMet := 0;
nFirst := 0;
nWentFirst := 0;
FOR nI := 1 TO nRows DO
  nR := nLb + nI - 1;
  nS := LOWER_BOUND(aConditionSettings, 1) + nI - 1;
  bBadSet := NOT CondOk(stS := aConditionSettings[nS]);
  (* not OK this long *)
  IF NOT aConditions[nR].bConditionMet AND NOT aConditions[nR].bNotMetNow THEN
    aConditions[nR].tWentNotMetAt := tNow;
  END_IF;
  aConditions[nR].bNotMetNow := NOT aConditions[nR].bConditionMet;
  bActive := aConditions[nR].bNotMetNow AND (aConditionSettings[nS].tTripDelay <= T#0s
                                 OR tNow - aConditions[nR].tWentNotMetAt >= aConditionSettings[nS].tTripDelay);
  IF aConditionSettings[nS].eResetMode = E_ResetMode.Auto AND NOT bBadSet THEN
    aConditions[nR].bLatched := FALSE;
  ELSIF bActive THEN
    aConditions[nR].bLatched := TRUE;
  ELSIF aConditions[nR].bLatched AND aConditions[nR].bConditionMet THEN
    IF bResetReq THEN
      aConditions[nR].bLatched := FALSE;
    ELSIF aConditionSettings[nS].eResetMode = E_ResetMode.Retry AND NOT bBadSet THEN
      IF aConditions[nR].nRetriesUsed > 0 AND tNow - aConditions[nR].tRetryWindowStartedAt >= refData.set.tRetryCountWindow THEN
        aConditions[nR].nRetriesUsed := 0;  (* a new window *)
      END_IF;
      IF aConditions[nR].nRetriesUsed < refData.set.nMaxRetriesBeforeLockout THEN
        IF aConditions[nR].nRetriesUsed = 0 THEN
          aConditions[nR].tRetryWindowStartedAt := tNow;
        END_IF;
        aConditions[nR].nRetriesUsed := aConditions[nR].nRetriesUsed + 1;
        aConditions[nR].bLatched := FALSE;   (* by itself, a few times *)
      END_IF;
    END_IF;
  END_IF;
  IF bResetReq AND aConditions[nR].bConditionMet THEN
    aConditions[nR].nRetriesUsed := 0;
  END_IF;
  IF aConditions[nR].bNotMetNow AND NOT bActive AND aConditionSettings[nS].tTripDelay > T#0s THEN
    aConditions[nR].tTripDelayTimeLeft := aConditionSettings[nS].tTripDelay - (tNow - aConditions[nR].tWentNotMetAt);
    IF tLeftMin = T#0s OR aConditions[nR].tTripDelayTimeLeft < tLeftMin THEN tLeftMin := aConditions[nR].tTripDelayTimeLeft; END_IF;
  ELSE
    aConditions[nR].tTripDelayTimeLeft := T#0s;
  END_IF;
  aConditions[nR].bWentNotMetThisScan := (bActive OR aConditions[nR].bLatched) AND NOT aConditions[nR].bTripped;
  aConditions[nR].bTripped := bActive OR aConditions[nR].bLatched;
  (* the bypass: allowed, asked, permitted, within the timeout *)
  IF NOT (aConditions[nR].bBypassRequest AND aConditionSettings[nS].bBypassAllowed
          AND bBypassKeyOn AND bOkSet) THEN
    aConditions[nR].bBypassLastScan := FALSE;
    aConditions[nR].bBypassInEffect := FALSE;
  ELSE
    IF NOT aConditions[nR].bBypassLastScan THEN
      aConditions[nR].bBypassLastScan := TRUE;
      aConditions[nR].tBypassStartedAt := tNow;
    END_IF;
    aConditions[nR].bBypassInEffect := refData.set.tBypassEndsAfter <= T#0s
                           OR tNow - aConditions[nR].tBypassStartedAt < refData.set.tBypassEndsAfter;
  END_IF;
  IF aConditions[nR].bBypassInEffect THEN
    aConditions[nR].tBypassedFor := tNow - aConditions[nR].tBypassStartedAt;
    IF refData.set.tBypassEndsAfter > T#0s THEN
      aConditions[nR].tBypassTimeLeft := refData.set.tBypassEndsAfter - aConditions[nR].tBypassedFor;
    ELSE
      aConditions[nR].tBypassTimeLeft := T#0s;
    END_IF;
  ELSE
    aConditions[nR].tBypassedFor := T#0s;
    aConditions[nR].tBypassTimeLeft := T#0s;
  END_IF;
  (* into the whole *)
  IF aConditions[nR].bBypassInEffect THEN
    bBypassInEffect := TRUE;
  ELSIF aConditions[nR].bTripped THEN
    bPermissive := FALSE;
    nConditionsNotMet := nConditionsNotMet + 1;
    IF nFirst = 0 THEN
      nFirst := nI;
    END_IF;
    IF aConditions[nR].bWentNotMetThisScan AND nWentFirst = 0 THEN
      nWentFirst := nI;
    END_IF;
  END_IF;
END_FOR;

(* first-out: kept until a reset; the one that went out first (same scan: the lowest) *)
IF nFirstOutCondition = 0 THEN
  IF nWentFirst > 0 THEN
    nFirstOutCondition := nWentFirst;
  ELSE
    nFirstOutCondition := nFirst;          (* after a reset (or power-up) with conditions still out *)
  END_IF;
END_IF;
IF bOkPrev AND NOT bPermissive THEN
  refData.sts.nTripCount := refData.sts.nTripCount + 1;
END_IF;
bOkPrev := bPermissive;

(* errors *)
bError := bCfgBad OR NOT bRowsOk OR NOT bOkSet;
bWarning := NOT bError AND (bBypassInEffect OR refData.sts.bSettingRefused);
IF bError THEN
  eErrorId := E_UtError.BadSetting;
ELSIF NOT bPermissive THEN
  eErrorId := E_UtError.ConditionOut;
ELSIF bBypassInEffect THEN
  eErrorId := E_UtError.Bypassed;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF NOT bPermissive THEN
  eState := E_State.Held;
ELSE
  eState := E_State.Running;
END_IF;
refData.sts.bPermissive := bPermissive;
refData.sts.nFirstOutCondition := nFirstOutCondition;
refData.sts.bBypassInEffect := bBypassInEffect;
refData.sts.nConditionsNotMet := nConditionsNotMet;
refData.sts.tTimeLeft := tLeftMin;
bFirstScan := FALSE;

END_FUNCTION_BLOCK
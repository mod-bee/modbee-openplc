(* FB_ReportArray — FB_Report for a list of values. Tables the project declares (VAR_IN_OUT, the same size): aItemSet
(each value's settings, ST_ReportSet, at most 16 kept) and aItem (each value's live row: the project writes
aItem[i].fIn and aItem[i].bInGood; the block writes bReport (one scan: send now), fValue, bGood, eReason in
aItem[i].stMem, and aItem[i].sts). Each row runs the FB_Report decision (F_ReportRun). bEnable FALSE holds every
item; bEnable back (link up / born) = every item reports First (with its and set.bReportOnStart); bForce /
bCmdForce = every item reports now, aItem[i].bCmdForce that item. set.tHeartbeat applies to items whose own is 0.
Pins: bEnable, bForce, refData, aItemSet, aItem -> bAnyReport, nReportCount, plus FB_Object's outputs. Kept (a
retained last-good copy, restored at power-up, a bad write put back, the row's sts.bRefused / eRefusedWhy): set and
the item
settings. An item with a bad setting and no good copy is left out: warning BadSetting, sts.nBadItem names it.
Tables of different sizes: error BadSetting. *)

FUNCTION_BLOCK FB_ReportArray EXTENDS FB_Object
  VAR_INPUT
    bEnable : BOOL := TRUE; (* link up / born: every item reports First *)
    bForce : BOOL R_EDGE; (* every item reports now *)
    refData : REFERENCE TO ST_ReportArrayData;
  END_VAR
  VAR_IN_OUT
    aItemSet : ARRAY [*] OF ST_REPORTSET;
    aItem : ARRAY [*] OF ST_REPORTITEM;
  END_VAR
  VAR_OUTPUT
    bAnyReport : BOOL;
    nReportCount : INT; (* items reporting this scan *)
  END_VAR
  VAR RETAIN
    stKept : ST_ReportArraySet;
    aKeptItem : ARRAY [1..16] OF ST_REPORTSET;
    nKeptMask : WORD; (* bit n-1: slot n holds a good copy (a row bad from the start has none) *)
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
    cMaxKept : DINT := 16;
  END_VAR
  VAR
    bCmdSeen : BOOL;
  END_VAR
  VAR_TEMP
    nBit : WORD; (* this row's bit in nKeptMask *)
    bOkSet : BOOL;
    bCfgBad : BOOL;
    bForceAll : BOOL;
    bRowOk : BOOL;
    nN : DINT;
    nI : DINT;
    nR : DINT;
    nS : DINT;
    tBeat : TIME;
    bRst : BOOL;
  END_VAR


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_ReportArraySet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.tHeartbeat >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_ReportArraySet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bAnyReport := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
nN := UPPER_BOUND(aItem, 1) - LOWER_BOUND(aItem, 1) + 1;
bCfgBad := UPPER_BOUND(aItemSet, 1) - LOWER_BOUND(aItemSet, 1) + 1 <> nN;
IF bCfgBad THEN
  nN := 0;
END_IF;

(* kept settings and item settings; a bad write is put back *)
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    FOR nI := 1 TO MIN(nN, cMaxKept) DO
      IF (nKeptMask AND SHL(WORD#1, nI - 1)) <> 0 THEN
        aItemSet[LOWER_BOUND(aItemSet, 1) + nI - 1] := aKeptItem[nI];
      END_IF;
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
  refData.sts.eRefusedWhy := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOkSet := TRUE;
END_IF;
bForceAll := bForce OR (refData.bCmdForce AND NOT bCmdSeen);
bCmdSeen := refData.bCmdForce;
refData.bCmdForce := FALSE;
bRst := bForceAll OR SystemReset();
IF bRst THEN
  refData.sts.bRefused := FALSE;
  refData.sts.eRefusedWhy := E_UtError.None;
END_IF;

bAnyReport := FALSE;
nReportCount := 0;
refData.sts.nBadItem := 0;
FOR nI := 1 TO nN DO
  nR := LOWER_BOUND(aItem, 1) + nI - 1;
  nS := LOWER_BOUND(aItemSet, 1) + nI - 1;
  nBit := 0;
  IF nI <= cMaxKept THEN
    nBit := SHL(WORD#1, nI - 1);
  END_IF;
  bRowOk := F_ReportSetOk(stS := aItemSet[nS]);
  IF bRowOk THEN
    IF nI <= cMaxKept THEN
      aKeptItem[nI] := aItemSet[nS];
      nKeptMask := nKeptMask OR nBit;
    END_IF;
  ELSIF nBit <> 0 AND (nKeptMask AND nBit) <> 0 THEN
    aItem[nR].sts.eRefusedWhy := F_ReportSetWhy(stS := aItemSet[nS]);
    refData.sts.eRefusedWhy := aItem[nR].sts.eRefusedWhy;
    aItemSet[nS] := aKeptItem[nI];
    aItem[nR].sts.bRefused := TRUE;
    refData.sts.bRefused := TRUE;
    bRowOk := TRUE;
  ELSIF refData.sts.nBadItem = 0 THEN
    refData.sts.nBadItem := DINT_TO_INT(nI);
  END_IF;
  IF bRst THEN
    aItem[nR].sts.bRefused := FALSE;
    aItem[nR].sts.eRefusedWhy := E_UtError.None;
  END_IF;
  IF bRowOk THEN
    tBeat := aItemSet[nS].tHeartbeat;
    IF tBeat <= T#0s THEN
      tBeat := refData.set.tHeartbeat;
    END_IF;
    IF F_ReportRun(tNow := tNow, fIn := aItem[nR].fIn, bInGood := aItem[nR].bInGood,
                   bForceReq := bForceAll OR (aItem[nR].bCmdForce AND NOT aItem[nR].bCmdSeen),
                   bEnable := bEnable, tHeartbeat := tBeat,
                   bOnStart := refData.set.bReportOnStart AND aItemSet[nS].bReportOnStart,
                   stS := aItemSet[nS], stM := aItem[nR].stMem, stSts := aItem[nR].sts) THEN
      bAnyReport := TRUE;
      nReportCount := nReportCount + 1;
      refData.sts.nReports := refData.sts.nReports + 1;
    END_IF;
  ELSE
    aItem[nR].stMem.bReport := FALSE;
  END_IF;
  aItem[nR].bCmdSeen := aItem[nR].bCmdForce;
  aItem[nR].bCmdForce := FALSE;
END_FOR;

bError := bCfgBad OR NOT bOkSet;
bWarning := NOT bError AND (refData.sts.nBadItem > 0 OR refData.sts.bRefused);
IF bError OR refData.sts.nBadItem > 0 THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF NOT bEnable THEN
  eState := E_State.Off;
ELSE
  eState := E_State.Running;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK
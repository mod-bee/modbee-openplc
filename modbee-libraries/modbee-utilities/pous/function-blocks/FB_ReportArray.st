(* FB_ReportArray — FB_Report for a list of values. Tables the project declares (VAR_IN_OUT, the same size): aItemSettings
(each value's settings, ST_ReportSet, at most 16 kept) and aItems (each value's live row: the project writes
aItems[i].fIn and aItems[i].bInputGood; the block writes bSendNow (one scan: send now), fValue, bGood, eReportReason in
aItems[i].stResult, and aItems[i].sts). Each row runs the FB_Report decision (F_ReportRun). bEnable FALSE holds every
item; bEnable back (link up / born) = every item reports First (with its and set.bReportOnStart); bReportNow /
bCmdReportNow = every item reports now, aItems[i].bCmdReportNow that item. set.tDefaultHeartbeatInterval applies to items whose own is 0.
Pins: bEnable, bReportNow, refData, aItemSettings, aItems -> bAnyReport, nItemsReporting, plus FB_Object's outputs. Kept (a
retained last-good copy, restored at power-up, a bad write put back, the row's sts.bSettingRefused / eSettingRefusedErrorId): set and
the item
settings. An item with a bad setting and no good copy is left out: warning BadSetting, sts.nBadSettingItem names it.
Tables of different sizes: error BadSetting. *)

FUNCTION_BLOCK FB_ReportArray EXTENDS FB_Object
  VAR_INPUT
    bEnable : BOOL := TRUE; (* link up / born: every item reports First *)
    bReportNow : BOOL R_EDGE; (* every item reports now *)
    refData : REFERENCE TO ST_ReportArrayData; (* the block's record *)
  END_VAR
  VAR_IN_OUT
    aItemSettings : ARRAY [*] OF ST_REPORTSET; (* each value's settings (at most 16 kept) *)
    aItems : ARRAY [*] OF ST_REPORTITEM; (* each value's live row: the project writes fIn and bInputGood; the block writes the result *)
  END_VAR
  VAR_OUTPUT
    bAnyReport : BOOL; (* an item reports this scan *)
    nItemsReporting : INT; (* items reporting this scan *)
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
  IF NOT (stS.tDefaultHeartbeatInterval >= T#0s) THEN
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
nN := UPPER_BOUND(aItems, 1) - LOWER_BOUND(aItems, 1) + 1;
bCfgBad := UPPER_BOUND(aItemSettings, 1) - LOWER_BOUND(aItemSettings, 1) + 1 <> nN;
IF bCfgBad THEN
  nN := 0;
END_IF;

(* kept settings and item settings; a bad write is put back *)
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    FOR nI := 1 TO MIN(nN, cMaxKept) DO
      IF (nKeptMask AND SHL(WORD#1, nI - 1)) <> 0 THEN
        aItemSettings[LOWER_BOUND(aItemSettings, 1) + nI - 1] := aKeptItem[nI];
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
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
  bOkSet := TRUE;
END_IF;
bForceAll := bReportNow OR (refData.bCmdReportNow AND NOT bCmdSeen);
bCmdSeen := refData.bCmdReportNow;
refData.bCmdReportNow := FALSE;
bRst := bForceAll OR SystemReset();
IF bRst THEN
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

bAnyReport := FALSE;
nItemsReporting := 0;
refData.sts.nBadSettingItem := 0;
FOR nI := 1 TO nN DO
  nR := LOWER_BOUND(aItems, 1) + nI - 1;
  nS := LOWER_BOUND(aItemSettings, 1) + nI - 1;
  nBit := 0;
  IF nI <= cMaxKept THEN
    nBit := SHL(WORD#1, nI - 1);
  END_IF;
  bRowOk := F_ReportSetOk(stSettings := aItemSettings[nS]);
  IF bRowOk THEN
    IF nI <= cMaxKept THEN
      aKeptItem[nI] := aItemSettings[nS];
      nKeptMask := nKeptMask OR nBit;
    END_IF;
  ELSIF nBit <> 0 AND (nKeptMask AND nBit) <> 0 THEN
    aItems[nR].sts.eSettingRefusedErrorId := F_ReportSetWhy(stSettings := aItemSettings[nS]);
    refData.sts.eSettingRefusedErrorId := aItems[nR].sts.eSettingRefusedErrorId;
    aItemSettings[nS] := aKeptItem[nI];
    aItems[nR].sts.bSettingRefused := TRUE;
    refData.sts.bSettingRefused := TRUE;
    bRowOk := TRUE;
  ELSIF refData.sts.nBadSettingItem = 0 THEN
    refData.sts.nBadSettingItem := DINT_TO_INT(nI);
  END_IF;
  IF bRst THEN
    aItems[nR].sts.bSettingRefused := FALSE;
    aItems[nR].sts.eSettingRefusedErrorId := E_UtError.None;
  END_IF;
  IF bRowOk THEN
    tBeat := aItemSettings[nS].tHeartbeatInterval;
    IF tBeat <= T#0s THEN
      tBeat := refData.set.tDefaultHeartbeatInterval;
    END_IF;
    IF F_ReportRun(tNow := tNow, fIn := aItems[nR].fIn, bInputGood := aItems[nR].bInputGood,
                   bReportNow := bForceAll OR (aItems[nR].bCmdReportNow AND NOT aItems[nR].bCmdReportNowTaken),
                   bEnable := bEnable, tHeartbeatInterval := tBeat,
                   bReportOnStart := refData.set.bReportOnStart AND aItemSettings[nS].bReportOnStart,
                   stSettings := aItemSettings[nS], stMemory := aItems[nR].stResult, stStatus := aItems[nR].sts) THEN
      bAnyReport := TRUE;
      nItemsReporting := nItemsReporting + 1;
      refData.sts.nSentCount := refData.sts.nSentCount + 1;
    END_IF;
  ELSE
    aItems[nR].stResult.bSendNow := FALSE;
  END_IF;
  aItems[nR].bCmdReportNowTaken := aItems[nR].bCmdReportNow;
  aItems[nR].bCmdReportNow := FALSE;
END_FOR;

bError := bCfgBad OR NOT bOkSet;
bWarning := NOT bError AND (refData.sts.nBadSettingItem > 0 OR refData.sts.bSettingRefused);
IF bError OR refData.sts.nBadSettingItem > 0 THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bSettingRefused THEN
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
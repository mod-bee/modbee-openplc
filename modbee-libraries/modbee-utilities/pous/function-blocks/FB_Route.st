(* FB_Route — the outlet selector (up to 4 outlet valves): which outlet the pumps deliver to, valve first, the
wet-weather divert to storage, an irrigator blocked.
Pins: bLevelRun (level pumping chooses the route), nRunOutlet (the outlet of a run / the zone watering, 1..4; > 0
also asks for it), bWanted (water wanted: a pump is asked or in Hand), bPumpRunning (never close under it; the
close delay starts when it drops), bToStorage (wet weather: FB_IrrDefer), bStorageFull, bIrrBlocked (the
irrigator's fail-safe tripped), ipValve1..4 (each outlet's valve, I_Equipment; NULL = not fitted), refData
-> nOutlet (in use, 0 none), bRouteOk (proven: -> the pumps' start hold), bRouteLost (-> the pumps' interlock),
bIsIrrigation, bIsStorage, nPreset (the outlet's speed preset; -1 = the speed control's own), plus FB_Object's
outputs.
The outlet in use: nRunOutlet 1..4 (never diverted; outside 0..4 refused, a warning) -> else bLevelRun ->
set.nLevelOutlet (an Irrigation outlet: with bToStorage or bIrrBlocked -> set.nStorageOutlet while it is set,
fitted and not full ("diverted"); with bToStorage and no storage it stays, warning NoStorage; with bIrrBlocked and
no storage nothing opens: RouteBlocked) -> else set.nRunOutlet (Hand, manual runs, zones that own their valves).
While bWanted OR bPumpRunning OR nRunOutlet > 0 the outlet in use gets Request(open) and every other outlet with a
kind Request(closed), every scan (one owner); kind None is never requested. Valve first: bRouteOk once the outlet
in use is open (its bIsRunning). An outlet change: the old outlet is released set.tCloseDelay after the new one is
proven; the last proven outlet is never released under a running pump; the request gone: released tCloseDelay
after the pumps stop. bRouteLost: a pump runs and no held outlet is open, or the outlet in use is blocked. Valves
move only in their own Auto (else warning NotAuto); proof in any mode. Every kind None = routing not used,
bRouteOk TRUE. Settings are kept (a retained last-good copy, a bad write put back). *)

FUNCTION_BLOCK FB_Route EXTENDS FB_Object
  VAR_INPUT
    bLevelRun : BOOL := FALSE;
    nRunOutlet : INT;
    bWanted : BOOL;
    bPumpRunning : BOOL;
    bToStorage : BOOL;
    bStorageFull : BOOL;
    bIrrBlocked : BOOL;
    ipValve1 : I_Equipment;
    ipValve2 : I_Equipment;
    ipValve3 : I_Equipment;
    ipValve4 : I_Equipment;
    refData : REFERENCE TO ST_RouteData;
  END_VAR
  VAR_OUTPUT
    nOutlet : INT;
    bRouteOk : BOOL;
    bRouteLost : BOOL;
    bIsIrrigation : BOOL;
    bIsStorage : BOOL;
    nPreset : INT := -1;
  END_VAR
  VAR RETAIN
    stKept : ST_RouteSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    nHoldMask : BYTE;
    nPrevMask : BYTE;
    tRelSince : TIME;
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    aV : ARRAY [1..4] OF I_EQUIPMENT;
    aFitted : ARRAY [1..4] OF BOOL;
    aIsOpen : ARRAY [1..4] OF BOOL;
    nK : INT;
    bUsed : BOOL;
    nOut : INT;
    bPurposeBad : BOOL;
    bStOk : BOOL;
    bDiverted : BOOL;
    bNoStorage : BOOL;
    bBlocked : BOOL;
    bRefusedNo : BOOL;
    bRequesting : BOOL;
    nReqMask : BYTE;
    nBit : BYTE;
    bOutProven : BOOL;
    bRelCond : BOOL;
    bAnyHeldOpen : BOOL;
    bNotAuto : BOOL;
    bOutFault : BOOL;
    bOtherFault : BOOL;
  END_VAR


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_RouteSet;
  END_VAR
  VAR
    nI : INT;
  END_VAR
  SetWhy := E_UtError.None;
  IF stS.nLevelOutlet > 4 OR stS.nRunOutlet > 4 OR stS.nStorageOutlet > 4 THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF stS.tCloseDelay < T#0s OR stS.tCloseDelay > T#10m THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
  FOR nI := 1 TO 4 DO
    IF SetWhy <> E_UtError.None THEN
      ;
    ELSIF NOT (stS.aOutlet[nI].eKind = E_OutletKind.None OR stS.aOutlet[nI].eKind = E_OutletKind.Irrigation
               OR stS.aOutlet[nI].eKind = E_OutletKind.Storage OR stS.aOutlet[nI].eKind = E_OutletKind.Other) THEN
      SetWhy := E_UtError.ChoiceBad;
    ELSIF stS.aOutlet[nI].nPreset < -1 THEN
      SetWhy := E_UtError.BelowMin;
    ELSIF stS.aOutlet[nI].nPreset > 2 THEN
      SetWhy := E_UtError.AboveMax;
    END_IF;
  END_FOR;
  IF SetWhy = E_UtError.None AND stS.nStorageOutlet >= 1 AND stS.nStorageOutlet <= 4 THEN
    IF stS.aOutlet[stS.nStorageOutlet].eKind <> E_OutletKind.Storage THEN
      SetWhy := E_UtError.ChoiceBad;       // the storage outlet is not of kind Storage
    END_IF;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_RouteSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bRouteOk := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
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
END_IF;
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eRefusedWhy := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOk := TRUE;
END_IF;
IF SystemReset() THEN
  refData.sts.bRefused := FALSE;
  refData.sts.eRefusedWhy := E_UtError.None;
END_IF;

(* the outlets *)
aV[1] := ipValve1;
aV[2] := ipValve2;
aV[3] := ipValve3;
aV[4] := ipValve4;
bUsed := FALSE;
FOR nK := 1 TO 4 DO
  aFitted[nK] := aV[nK] <> NULL;
  aIsOpen[nK] := FALSE;
  IF aV[nK] <> NULL THEN
    aIsOpen[nK] := aV[nK].bIsRunning;   (* a valve "runs" while open *)
  END_IF;
  IF refData.set.aOutlet[nK].eKind <> E_OutletKind.None THEN
    bUsed := TRUE;
  END_IF;
END_FOR;

(* which outlet *)
nOut := 0;
bPurposeBad := FALSE;
bDiverted := FALSE;
bNoStorage := FALSE;
bRefusedNo := FALSE;
bStOk := FALSE;
IF refData.set.nStorageOutlet >= 1 AND refData.set.nStorageOutlet <= 4 THEN
  bStOk := refData.set.aOutlet[refData.set.nStorageOutlet].eKind = E_OutletKind.Storage
           AND aFitted[refData.set.nStorageOutlet];
END_IF;
IF nRunOutlet >= 1 AND nRunOutlet <= 4 THEN
  nOut := nRunOutlet;
ELSIF nRunOutlet <> 0 THEN
  bRefusedNo := TRUE;             (* e.g. zone 5 on a 4-outlet route *)
ELSIF bLevelRun THEN
  nOut := USINT_TO_INT(refData.set.nLevelOutlet);
  IF nOut >= 1 AND nOut <= 4 THEN
    IF refData.set.aOutlet[nOut].eKind = E_OutletKind.Irrigation AND (bToStorage OR bIrrBlocked) THEN
      IF bStOk AND NOT bStorageFull THEN
        nOut := USINT_TO_INT(refData.set.nStorageOutlet);
        bDiverted := TRUE;
      ELSIF bToStorage AND NOT bIrrBlocked THEN
        bNoStorage := TRUE;       (* an overflow is the worse breach: stay *)
      END_IF;
    END_IF;
  END_IF;
ELSE
  nOut := USINT_TO_INT(refData.set.nRunOutlet);
END_IF;
IF nOut > 4 THEN
  nOut := 0;
  bPurposeBad := TRUE;
END_IF;
IF nOut >= 1 AND bUsed THEN
  IF refData.set.aOutlet[nOut].eKind = E_OutletKind.None OR NOT aFitted[nOut] THEN
    bPurposeBad := TRUE;
  END_IF;
END_IF;
bBlocked := FALSE;
IF nOut >= 1 AND NOT bPurposeBad THEN
  bBlocked := refData.set.aOutlet[nOut].eKind = E_OutletKind.Irrigation AND bIrrBlocked;
END_IF;
IF NOT bUsed THEN
  nOut := 0;
END_IF;

(* the requests: the outlet in use open, the others held until the release *)
bRequesting := bWanted OR bPumpRunning OR nRunOutlet > 0;
bOutProven := FALSE;
IF nOut >= 1 AND NOT bPurposeBad AND NOT bBlocked THEN
  bOutProven := aIsOpen[nOut];
END_IF;
nReqMask := BYTE#0;
IF bRequesting AND nOut >= 1 AND NOT bPurposeBad AND NOT bBlocked THEN
  nReqMask := SHL(BYTE#1, nOut - 1);
END_IF;
IF nReqMask <> nPrevMask THEN
  tRelSince := tNow;              (* the delay counts from the request ending, not from the opening *)
  nPrevMask := nReqMask;
END_IF;
bRelCond := (bRequesting AND bOutProven) OR (NOT bRequesting AND NOT bPumpRunning) OR bBlocked
            OR (bRequesting AND nOut = 0);
IF NOT bRelCond THEN
  tRelSince := tNow;
END_IF;
IF bRelCond AND tNow - tRelSince >= refData.set.tCloseDelay THEN
  nHoldMask := BYTE#0;
END_IF;
nHoldMask := nHoldMask AND NOT nReqMask;
bAnyHeldOpen := FALSE;
bNotAuto := FALSE;
bOutFault := FALSE;
bOtherFault := FALSE;
refData.sts.nFaultOutlet := 0;
refData.sts.nProvenMask := BYTE#0;
FOR nK := 1 TO 4 DO
  nBit := SHL(BYTE#1, nK - 1);
  IF aIsOpen[nK] THEN
    refData.sts.nProvenMask := refData.sts.nProvenMask OR nBit;
  END_IF;
  IF refData.set.aOutlet[nK].eKind <> E_OutletKind.None AND aFitted[nK] THEN
    aV[nK].Request(bRun := ((nReqMask OR nHoldMask) AND nBit) <> BYTE#0, bHold := FALSE);
    IF ((nReqMask OR nHoldMask) AND nBit) <> BYTE#0 AND aIsOpen[nK] THEN
      bAnyHeldOpen := TRUE;
    END_IF;
    IF nK = nOut AND bRequesting AND NOT aV[nK].bIsAuto THEN
      bNotAuto := TRUE;
    END_IF;
    IF nK = nOut AND aV[nK].bIsFaulted THEN
      bOutFault := TRUE;
      refData.sts.nFaultOutlet := INT_TO_USINT(nK);
    ELSIF nK <> nOut AND aV[nK].bIsFaulted THEN
      bOtherFault := TRUE;
    END_IF;
  END_IF;
END_FOR;
nHoldMask := nHoldMask OR nReqMask;   (* what is requested now is held until a release *)

(* proof *)
IF NOT bUsed THEN
  bRouteOk := TRUE;
ELSIF bRefusedNo OR bPurposeBad OR bBlocked OR NOT bOk THEN
  bRouteOk := FALSE;
ELSIF nOut = 0 THEN
  bRouteOk := TRUE;
ELSE
  bRouteOk := bOutProven;
END_IF;
bRouteLost := bUsed AND bPumpRunning AND nOut >= 1 AND (bBlocked OR NOT bAnyHeldOpen);

(* outputs *)
nOutlet := nOut;
bIsIrrigation := FALSE;
bIsStorage := FALSE;
nPreset := -1;
refData.sts.eKind := E_OutletKind.None;
IF nOut >= 1 THEN
  refData.sts.eKind := refData.set.aOutlet[nOut].eKind;
  bIsIrrigation := refData.set.aOutlet[nOut].eKind = E_OutletKind.Irrigation;
  bIsStorage := refData.set.aOutlet[nOut].eKind = E_OutletKind.Storage;
  nPreset := SINT_TO_INT(refData.set.aOutlet[nOut].nPreset);
END_IF;
IF (nHoldMask AND NOT nReqMask) <> BYTE#0 AND bRelCond AND refData.set.tCloseDelay > tNow - tRelSince THEN
  refData.sts.tTimeLeft := refData.set.tCloseDelay - (tNow - tRelSince);
ELSE
  refData.sts.tTimeLeft := T#0s;
END_IF;
refData.sts.nOutlet := INT_TO_USINT(nOut);
refData.sts.nOpenMask := nHoldMask;
refData.sts.bRouteOk := bRouteOk;
refData.sts.bRouteLost := bRouteLost;
refData.sts.bOpening := bRequesting AND nOut >= 1 AND NOT bOutProven;
refData.sts.bClosing := (nHoldMask AND NOT nReqMask) <> BYTE#0;
refData.sts.bDiverted := bDiverted;
refData.sts.bNoStorage := bNoStorage;
refData.sts.bBlocked := bBlocked OR (bLevelRun AND bIrrBlocked AND NOT bDiverted AND nRunOutlet = 0);

(* errors *)
bError := bUsed AND (bOutFault OR bPurposeBad OR bRouteLost OR NOT bOk);
bWarning := NOT bError AND (bNoStorage OR bNotAuto OR bOtherFault OR bRefusedNo OR refData.sts.bBlocked
                            OR refData.sts.bRefused);
IF NOT bOk OR bPurposeBad THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bRouteLost THEN
  eErrorId := E_UtError.RouteLost;
ELSIF bOutFault THEN
  eErrorId := E_UtError.ConditionOut;
ELSIF refData.sts.bBlocked THEN
  eErrorId := E_UtError.RouteBlocked;
ELSIF bRefusedNo THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bNoStorage THEN
  eErrorId := E_UtError.NoStorage;
ELSIF bNotAuto THEN
  eErrorId := E_UtError.NotAuto;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF NOT bUsed OR NOT bRequesting THEN
  eState := E_State.Idle;
ELSIF NOT bRouteOk THEN
  eState := E_State.Starting;
ELSE
  eState := E_State.Running;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK
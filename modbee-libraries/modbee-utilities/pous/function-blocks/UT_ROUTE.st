(* UT_ROUTE — outlet selector (up to 4 outlet valves): which outlet the pumps
deliver to, valve first, wet-weather divert to storage, irrigator blocked.

Outlet in use: RunOutlet 1..4 (a run / the zone watering; never diverted;
outside 0..4 refused) -> else LevelRun -> levelOutlet (an IRRIGATION outlet:
with ToStorage or IrrBlocked -> storageOutlet while set, fitted and not
StorageFull, "Diverted"; with ToStorage and no storage it stays, warning
"no storage"; with IrrBlocked and no storage nothing opens: blocked) ->
else runOutlet (Hand, manual runs, zones that own their valves).
While Wanted OR PumpRunning OR RunOutlet > 0 the outlet in use gets
Request(open, NaN, tag) and every other outlet with a kind Request(closed),
every scan (one owner). Kind NONE is never requested. Valve first: RouteOk
(the outlet in use IsOpen) -> the pumps' StartHold. An outlet change: the old
outlet is released closeDelay after the new one is proven; the last proven
outlet is never released under a running pump; request gone: released
closeDelay after the pumps stop. RouteLost: a pump runs and no held outlet
is open, or the outlet in use is blocked -> the pumps' Interlock. Valves move
only in their own Auto (else warning); proof is IsOpen in any mode. Defaults
(every kind NONE) = routing not used, RouteOk TRUE. Settings kept; a bad
write is put back. *)

FUNCTION_BLOCK UT_ROUTE
  VAR_INPUT
    LevelRun : BOOL; (* level pumping chooses the route *)
    RunOutlet : INT; (* outlet of a run / the zone watering; > 0 also asks for it *)
    Wanted : BOOL; (* water wanted: a pump is asked or in Hand *)
    PumpRunning : BOOL; (* never close under it; the close delay starts when it drops *)
    ToStorage : BOOL; (* wet weather *)
    StorageFull : BOOL; (* no divert, still irrigate *)
    IrrBlocked : BOOL; (* irrigator fail-safe tripped *)
    Valve1 : UT_I_VALVE; (* outlet 1's valve; NULL = not fitted *)
    Valve2 : UT_I_VALVE;
    Valve3 : UT_I_VALVE;
    Valve4 : UT_I_VALVE;
  END_VAR
  VAR_OUTPUT
    Outlet : INT; (* outlet in use (0 none) *)
    RouteOk : BOOL; (* proven -> the pumps' StartHold (NC) *)
    RouteLost : BOOL; (* -> the pumps' Interlock (NC) *)
    IsIrrigation : BOOL;
    IsStorage : BOOL;
    Preset : INT := -1; (* the outlet's speed preset; -1 = the speed control's own *)
    Fault : BOOL;
    Warning : BOOL;
  END_VAR
  VAR_IN_OUT
    Data : UT_ROUTE_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_ROUTE_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    vlv : ARRAY [1..4] OF UT_I_VALVE; (* the four valve pins, by outlet number *)
    keep : UT_KEEP;
    ok : BOOL;
    cfgId : UT_FAULT;
    tCur : TIME;
    k : INT;
    zero : REAL;
    nan : REAL;
    fitted : ARRAY [1..4] OF BOOL;
    isOpen : ARRAY [1..4] OF BOOL;
    used : BOOL;
    out : INT;
    purposeBad : BOOL;
    purposeId : UT_FAULT;
    stOk : BOOL; (* the storage outlet can take a divert *)
    diverted : BOOL;
    divertIrr : BOOL;
    noStorage : BOOL;
    blocked : BOOL;
    refusedNo : BOOL;
    requesting : BOOL;
    reqMask : BYTE; (* bit strings: NOT / AND / OR are bitwise only on ANY_BIT *)
    holdMask : BYTE;
    bit : BYTE;
    outProven : BOOL;
    relCond : BOOL;
    relSince : TIME;
    prevMask : BYTE; (* the request of the last scan: a change restarts the close delay *)
    anyHeldOpen : BOOL;
    refused : BOOL;
    notAuto : BOOL;
    otherWarn : BOOL;
    outFault : BOOL;
    x : BOOL;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
  END_VAR


tCur := TIME();
vlv[1] := Valve1;
vlv[2] := Valve2;
vlv[3] := Valve3;
vlv[4] := Valve4;
IF NOT (nan <> nan) THEN
  nan := zero / zero;
END_IF;
keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := UT_ROUTE_CHECK(S := Data.set, Id => cfgId);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := cfgId;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := UT_ROUTE_CHECK(S := Data.set, Id => cfgId);
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;

(* the outlets *)
used := FALSE;
FOR k := 1 TO 4 DO
  fitted[k] := FALSE;
  isOpen[k] := FALSE;
  IF vlv[k] <> NULL THEN
    fitted[k] := vlv[k].IsFitted();
    isOpen[k] := vlv[k].IsOpenNow();
  END_IF;
  IF Data.set.outlet[k].kind <> UT_OUT_NONE THEN
    used := TRUE;
  END_IF;
END_FOR;

(* which outlet *)
out := 0;
purposeBad := FALSE;
purposeId := UT_F_NONE;
diverted := FALSE;
divertIrr := FALSE;
noStorage := FALSE;
refusedNo := FALSE;
stOk := FALSE;
IF Data.set.storageOutlet >= 1 AND Data.set.storageOutlet <= 4 THEN
  stOk := Data.set.outlet[Data.set.storageOutlet].kind = UT_OUT_STORAGE AND fitted[Data.set.storageOutlet];
END_IF;
IF RunOutlet >= 1 AND RunOutlet <= 4 THEN
  out := RunOutlet;
ELSIF RunOutlet <> 0 THEN
  refusedNo := TRUE;             (* e.g. zone 5 on a 4-outlet route *)
ELSIF LevelRun THEN
  out := USINT_TO_INT(Data.set.levelOutlet);
  IF out >= 1 THEN
    IF Data.set.outlet[out].kind = UT_OUT_IRRIGATION AND (ToStorage OR IrrBlocked) THEN
      IF stOk AND NOT StorageFull THEN
        out := USINT_TO_INT(Data.set.storageOutlet);
        diverted := TRUE;
        divertIrr := IrrBlocked;
      ELSIF ToStorage AND NOT IrrBlocked THEN
        noStorage := TRUE;       (* an overflow is the worse breach: stay *)
      END_IF;
    END_IF;
  END_IF;
ELSE
  out := USINT_TO_INT(Data.set.runOutlet);
END_IF;
IF out > 4 THEN
  out := 0;                      (* a bad outlet number at first boot *)
  purposeBad := TRUE;
  purposeId := UT_F_OUTLET_NUMBER;
END_IF;
IF out >= 1 AND used THEN
  IF Data.set.outlet[out].kind = UT_OUT_NONE THEN
    purposeBad := TRUE;
    purposeId := UT_F_OUTLET_KIND;
  ELSIF NOT fitted[out] THEN
    purposeBad := TRUE;
    purposeId := UT_F_OUTLET_NOT_FITTED;
  END_IF;
END_IF;
blocked := FALSE;
IF out >= 1 AND NOT purposeBad THEN
  blocked := Data.set.outlet[out].kind = UT_OUT_IRRIGATION AND IrrBlocked;
END_IF;
IF NOT used THEN
  out := 0;
END_IF;

(* the requests: the outlet in use open, the others held until the release *)
requesting := Wanted OR PumpRunning OR RunOutlet > 0;
outProven := out >= 1 AND NOT purposeBad AND NOT blocked;
IF outProven THEN
  outProven := isOpen[out];
END_IF;
reqMask := 0;
IF requesting AND out >= 1 AND NOT purposeBad AND NOT blocked THEN
  reqMask := SHL(BYTE#1, out - 1);
END_IF;
IF reqMask <> prevMask THEN
  relSince := tCur;              (* the delay counts from the request ending, not from the opening *)
  prevMask := reqMask;
END_IF;
relCond := (requesting AND outProven) OR (NOT requesting AND NOT PumpRunning) OR blocked
           OR (requesting AND out = 0);
IF NOT relCond THEN
  relSince := tCur;
END_IF;
IF relCond AND tCur - relSince >= Data.set.closeDelay THEN
  holdMask := 0;
END_IF;
holdMask := holdMask AND NOT reqMask;
anyHeldOpen := FALSE;
refused := FALSE;
notAuto := FALSE;
otherWarn := FALSE;
outFault := FALSE;
Data.sts.faultOutlet := 0;
Data.sts.provenMask := 0;
FOR k := 1 TO 4 DO
  bit := SHL(BYTE#1, k - 1);
  IF isOpen[k] THEN
    Data.sts.provenMask := Data.sts.provenMask OR bit;
  END_IF;
  IF Data.set.outlet[k].kind <> UT_OUT_NONE AND fitted[k] THEN
    IF NOT vlv[k].Request(ReqOpen := ((reqMask OR holdMask) AND bit) <> 0, ReqPos := nan, Owner := Data.set.tag) THEN
      IF k = out THEN refused := TRUE; END_IF;
    END_IF;
    IF ((reqMask OR holdMask) AND bit) <> 0 AND isOpen[k] THEN
      anyHeldOpen := TRUE;
    END_IF;
    IF k = out AND requesting AND NOT vlv[k].IsAuto() THEN
      notAuto := TRUE;
    END_IF;
    IF k = out AND vlv[k].HasFault() THEN
      outFault := TRUE;
      Data.sts.faultOutlet := INT_TO_USINT(k);
    ELSIF k <> out AND (vlv[k].HasFault() OR vlv[k].HasWarning()) THEN
      otherWarn := TRUE;
    END_IF;
  END_IF;
END_FOR;
holdMask := holdMask OR reqMask;   (* what is requested now is held until a release *)

(* proof *)
IF NOT used THEN
  RouteOk := TRUE;
ELSIF refusedNo OR purposeBad OR blocked OR NOT ok THEN
  RouteOk := FALSE;
ELSIF out = 0 THEN
  RouteOk := TRUE;
ELSE
  RouteOk := outProven;
END_IF;
RouteLost := used AND PumpRunning AND out >= 1 AND (blocked OR NOT anyHeldOpen);

(* outputs *)
Outlet := out;
IsIrrigation := FALSE;
IsStorage := FALSE;
Preset := -1;
Data.sts.kind := UT_OUT_NONE;
IF out >= 1 THEN
  Data.sts.kind := Data.set.outlet[out].kind;
  IsIrrigation := Data.set.outlet[out].kind = UT_OUT_IRRIGATION;
  IsStorage := Data.set.outlet[out].kind = UT_OUT_STORAGE;
  Preset := SINT_TO_INT(Data.set.outlet[out].preset);
END_IF;
Fault := used AND (outFault OR refused OR purposeBad OR RouteLost OR NOT ok);
Warning := noStorage OR notAuto OR otherWarn OR refusedNo;
IF (holdMask AND NOT reqMask) <> 0 AND relCond AND Data.set.closeDelay > tCur - relSince THEN
  Data.det.timeLeft := Data.set.closeDelay - (tCur - relSince);
ELSE
  Data.det.timeLeft := T#0s;
END_IF;

stF := UT_F_NONE;
IF NOT ok THEN
  stCode := UT_ST_CONFIG;
  stF := cfgId;
ELSIF NOT used THEN
  stCode := UT_ST_IDLE;
ELSIF purposeBad THEN
  stCode := UT_ST_CONFIG;
  stF := purposeId;
ELSIF RouteLost THEN
  stCode := UT_ST_FAULT;
  stF := UT_F_NOT_PROVEN;
ELSIF outFault THEN
  stCode := UT_ST_FAULT;
  stF := vlv[out].FaultId();
ELSIF refused THEN
  stCode := UT_ST_FAULT;
  stF := UT_F_TWO_OWNERS;
ELSIF blocked OR (LevelRun AND IrrBlocked AND NOT diverted AND RunOutlet = 0) THEN
  stCode := UT_ST_ROUTE_BLOCKED;
  stF := UT_F_IRR_BLOCKED;
ELSIF refusedNo THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_OUTLET_NUMBER;
ELSIF noStorage THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_NO_STORAGE;
ELSIF notAuto THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_NOT_AUTO;
ELSIF divertIrr THEN
  stCode := UT_ST_DIVERTED_IRR;
ELSIF diverted THEN
  stCode := UT_ST_DIVERTED;
ELSIF requesting AND out >= 1 AND NOT outProven THEN
  stCode := UT_ST_OPENING;
ELSIF (holdMask AND NOT reqMask) <> 0 THEN
  stCode := UT_ST_CLOSING;
ELSIF requesting AND out >= 1 THEN
  stCode := UT_ST_OPEN;
ELSE
  stCode := UT_ST_IDLE;
END_IF;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
Data.sts.ne107 := UT_NE107_RUN(Fault := Fault, Check := FALSE, OutOfSpec := Warning, Maint := FALSE);
Data.sts.outlet := INT_TO_USINT(out);
Data.sts.openMask := holdMask;
Data.sts.routeOk := RouteOk;
Data.sts.routeLost := RouteLost;
Data.sts.opening := requesting AND out >= 1 AND NOT outProven;
Data.sts.closing := (holdMask AND NOT reqMask) <> 0;
Data.sts.diverted := diverted;
Data.sts.noStorage := noStorage;
Data.sts.blocked := stCode = UT_ST_ROUTE_BLOCKED;
Data.sts.fault := Fault;
Data.sts.warning := Warning;
Data.sts.configBad := NOT ok OR purposeBad;

END_FUNCTION_BLOCK
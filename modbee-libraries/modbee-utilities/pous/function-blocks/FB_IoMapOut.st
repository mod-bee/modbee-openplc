(* FB_IoMapOut — the output side of the IO map: functions to terminals, from the rows (DESIGN-0.2.md section 5.6;
src-v2 UT_IO_MAP_OUT). Call it LAST in the scan, after all logic, before your IO code copies the image to the
hardware.

Pins: bForcePermit (outputs may be forced only while TRUE: wire the system Off; dropping it releases every
output force; unwired: never), bReleaseAll (release every output force now and refuse new ones), refData
(set.tForceTime; counts) and the tables (VAR_IN_OUT, sized by the project): aDoSet / aDo (digital output
functions: rows / live), aAoSet / aAo (analog), aDoImg / aAoImg (the terminals: your IO code reads bQ / fV),
aMods (the module table, shared with FB_IoMapIn), aForce (the force slots, shared; never retained)
-> bAllOk, bAnyForced, bConfigBad (a wrong address, a function on a module not fitted, two functions on one
output, tables that do not match or are longer than the kept copy), the IO page's bit words dwTermBits /
dwForcedBits (the first 32 digital terminals), dwFnBits / dwOkBits / dwHeldBits (the first 32 digital
functions: bQ wanted, bOk, bHoldOff), plus FB_Object's bError / bWarning / eErrorId / eState.

The block owns the output image: every scan it first turns every output channel off (analog 0.0), then writes
each function's bQ / fV to its channel; a force takes the place of the function's value. So a channel with no
function is off, and a function moved to another channel leaves nothing behind. One channel carries one
function: a second one on it is not written (eWhy Shared, a configuration fault). A function's bOk is TRUE when
its channel is fitted, answering and good; eWhy says what is wrong otherwise; bFit says it is mapped on this
site. bHoldOff (per digital function) holds the output off even while forced (eWhy Blocked): wire a motor's
bHoldOff into it, so a commissioning force can never run a tripped motor.
Forcing: a slot names a channel (eKind DigitalOut or AnalogOut, eSrc, nModule, nCh), so spare outputs can be tested too;
only while bForcePermit; it ends by itself after set.tForceTime (1 ms .. 10 min, default 5 s), bCmdForce again
starts the time again, bCmdRelease or bReleaseAll end it at once, every force ends at power-up.
Errors: bError for a configuration fault (IoArraySize, IoAddress, IoShared, IoNotFitted) or rows that were
never good (BadSetting); bWarning for IoForced, IoMissing, IoBad, SettingRefused.

Kept settings (a retained last-good copy, restored at power-up, a bad write put back, sts.bRefused): each row
is its address packed into one DWORD (F_IoAddrPack: bits 0..2 eSrc, 3..9 nModule 0..127, 10..17 nCh). The
first 32 digital and 4 analog rows are kept, with set.tForceTime and the layout number: 38 retained values.
A row with an unknown source or a module over 127 is a bad write and put back.
Forces stay in the maps (see FB_IoMapIn); the slot logic is the shared F_IoForceSlot. *)

FUNCTION_BLOCK FB_IoMapOut EXTENDS FB_Object
  VAR_INPUT
    bForcePermit : BOOL; (* outputs may be forced only while TRUE (system Off); unwired: never *)
    bReleaseAll : BOOL; (* release every output force now and refuse new ones *)
    refData : REFERENCE TO ST_IoMapData;
  END_VAR
  VAR_IN_OUT
    aDoSet : ARRAY [*] OF ST_IODOSET;
    aDo : ARRAY [*] OF ST_IODO;
    aAoSet : ARRAY [*] OF ST_IOAOSET;
    aAo : ARRAY [*] OF ST_IOAO;
    aDoImg : ARRAY [*] OF ST_IODCH;
    aAoImg : ARRAY [*] OF ST_IOACH;
    aMods : ARRAY [*] OF ST_IOMODULE;
    aForce : ARRAY [*] OF ST_IOFORCE;
  END_VAR
  VAR_OUTPUT
    bAllOk : BOOL;
    bAnyForced : BOOL;
    bConfigBad : BOOL;
    dwTermBits : DWORD;
    dwFnBits : DWORD;
    dwOkBits : DWORD;
    dwForcedBits : DWORD;
    dwHeldBits : DWORD;
  END_VAR
  VAR RETAIN
    aKeptDo : ARRAY [1..32] OF DWORD;
    aKeptAo : ARRAY [1..4] OF DWORD;
    tKeptForceTime : TIME;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
    cDoKept : DINT := 32;
    cAoKept : DINT := 4;
  END_VAR
  VAR
    bBegun : BOOL;
  END_VAR
  VAR_TEMP
    bSizeBad : BOOL;
    bSetOk : BOOL;
    bRestore : BOOL;
    nD : DINT;
    nA : DINT;
    nI : DINT;
    nJ : DINT;
    nK : DINT;
    nSj : DINT;
    nM : DINT;
    nIdx : DINT;
    dLo : DINT;
    dHi : DINT;
    aLo : DINT;
    aHi : DINT;
    eWhere : E_IoQ;
    eKind : E_IoKind;
    tFt : TIME;
    eSrc : E_IoSrc;
    nMod : USINT;
    nCh : USINT;
    bX : BOOL;
    nForced : INT;
    nBad : INT;
    nAddr : INT;
    nShared : INT;
    nNotFit : INT;
    nMissFn : INT;
    nChBad : INT;
    nMissMod : INT;
    tLeftMax : TIME;
  END_VAR


IF NOT __ISVALIDREF(refData) THEN
  bAllOk := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
bSizeBad := UPPER_BOUND(aDoSet, 1) - LOWER_BOUND(aDoSet, 1) <> UPPER_BOUND(aDo, 1) - LOWER_BOUND(aDo, 1)
            OR UPPER_BOUND(aAoSet, 1) - LOWER_BOUND(aAoSet, 1) <> UPPER_BOUND(aAo, 1) - LOWER_BOUND(aAo, 1);
nD := MIN(UPPER_BOUND(aDoSet, 1) - LOWER_BOUND(aDoSet, 1), UPPER_BOUND(aDo, 1) - LOWER_BOUND(aDo, 1)) + 1;
nA := MIN(UPPER_BOUND(aAoSet, 1) - LOWER_BOUND(aAoSet, 1), UPPER_BOUND(aAo, 1) - LOWER_BOUND(aAo, 1)) + 1;
bSizeBad := bSizeBad OR nD > cDoKept OR nA > cAoKept;
IF refData.bCmdReset THEN
  refData.bCmdReset := FALSE;
  refData.sts.bRefused := FALSE;
END_IF;

(* 0. the rows: the kept copy at power-up, a bad write put back *)
bRestore := bFirstScan AND nKeptLayout = cLayout;
IF NOT bRestore THEN
  bSetOk := refData.set.tForceTime >= T#1ms AND refData.set.tForceTime <= T#10m;
  FOR nI := 1 TO nD DO
    nSj := LOWER_BOUND(aDoSet, 1) + nI - 1;
    IF NOT F_IoAddrOk(eSrc := aDoSet[nSj].eSrc, nModule := aDoSet[nSj].nModule) THEN
      bSetOk := FALSE;
    END_IF;
  END_FOR;
  FOR nI := 1 TO nA DO
    nSj := LOWER_BOUND(aAoSet, 1) + nI - 1;
    IF NOT F_IoAddrOk(eSrc := aAoSet[nSj].eSrc, nModule := aAoSet[nSj].nModule) THEN
      bSetOk := FALSE;
    END_IF;
  END_FOR;
  IF NOT bSetOk AND nKeptLayout = cLayout THEN
    bRestore := TRUE;
    refData.sts.bRefused := TRUE;
  END_IF;
END_IF;
IF bRestore THEN
  refData.set.tForceTime := tKeptForceTime;
  FOR nI := 1 TO MIN(nD, cDoKept) DO
    nSj := LOWER_BOUND(aDoSet, 1) + nI - 1;
    bX := F_IoAddrUnpack(dwAddr := aKeptDo[nI], eSrc => eSrc, nModule => nMod, nCh => nCh);
    aDoSet[nSj].eSrc := eSrc;
    aDoSet[nSj].nModule := nMod;
    aDoSet[nSj].nCh := nCh;
  END_FOR;
  FOR nI := 1 TO MIN(nA, cAoKept) DO
    nSj := LOWER_BOUND(aAoSet, 1) + nI - 1;
    bX := F_IoAddrUnpack(dwAddr := aKeptAo[nI], eSrc => eSrc, nModule => nMod, nCh => nCh);
    aAoSet[nSj].eSrc := eSrc;
    aAoSet[nSj].nModule := nMod;
    aAoSet[nSj].nCh := nCh;
  END_FOR;
  bSetOk := TRUE;                 // only good rows are ever kept
END_IF;
IF bSetOk THEN
  tKeptForceTime := refData.set.tForceTime;
  FOR nI := 1 TO MIN(nD, cDoKept) DO
    nSj := LOWER_BOUND(aDoSet, 1) + nI - 1;
    aKeptDo[nI] := F_IoAddrPack(eSrc := aDoSet[nSj].eSrc, nModule := aDoSet[nSj].nModule, nCh := aDoSet[nSj].nCh);
  END_FOR;
  FOR nI := 1 TO MIN(nA, cAoKept) DO
    nSj := LOWER_BOUND(aAoSet, 1) + nI - 1;
    aKeptAo[nI] := F_IoAddrPack(eSrc := aAoSet[nSj].eSrc, nModule := aAoSet[nSj].nModule, nCh := aAoSet[nSj].nCh);
  END_FOR;
  nKeptLayout := cLayout;
END_IF;
tFt := refData.set.tForceTime;
IF tFt <= T#0s THEN
  tFt := T#5s;
ELSIF tFt > T#10m THEN
  tFt := T#10m;
END_IF;
dLo := LOWER_BOUND(aDoImg, 1);
dHi := UPPER_BOUND(aDoImg, 1);
aLo := LOWER_BOUND(aAoImg, 1);
aHi := UPPER_BOUND(aAoImg, 1);

(* 1. every output channel off; nothing forced, no function yet *)
FOR nJ := dLo TO dHi DO
  aDoImg[nJ].bQ := FALSE;
  aDoImg[nJ].bForced := FALSE;
  aDoImg[nJ].nFn := 0;
END_FOR;
FOR nJ := aLo TO aHi DO
  aAoImg[nJ].fV := 0.0;
  aAoImg[nJ].bForced := FALSE;
  aAoImg[nJ].nFn := 0;
END_FOR;

(* 2. the output modules *)
nMissMod := 0;
FOR nK := LOWER_BOUND(aMods, 1) TO UPPER_BOUND(aMods, 1) DO
  IF aMods[nK].eKind = E_IoKind.DigitalOut OR aMods[nK].eKind = E_IoKind.AnalogOut THEN
    aMods[nK].nUsed := 0;
    IF NOT aMods[nK].bFitted THEN
      aMods[nK].eState := E_IoQ.NotFitted;
    ELSIF NOT aMods[nK].bOk THEN
      aMods[nK].eState := E_IoQ.Missing;
      nMissMod := nMissMod + 1;
    ELSE
      aMods[nK].eState := E_IoQ.Ok;
    END_IF;
  END_IF;
END_FOR;

(* 3. the force slots for outputs: the forced value goes on the terminal *)
nForced := 0;
tLeftMax := T#0s;
FOR nJ := LOWER_BOUND(aForce, 1) TO UPPER_BOUND(aForce, 1) DO
  eKind := aForce[nJ].eKind;
  IF eKind = E_IoKind.DigitalOut OR eKind = E_IoKind.AnalogOut THEN
    IF eKind = E_IoKind.DigitalOut THEN
      eWhere := F_IoFind(aMods := aMods, eKind := eKind, eSrc := aForce[nJ].eSrc, nModule := aForce[nJ].nModule,
                         nCh := aForce[nJ].nCh, nImgLo := dLo, nImgHi := dHi, nMod => nM, nIdx => nIdx);
    ELSE
      eWhere := F_IoFind(aMods := aMods, eKind := eKind, eSrc := aForce[nJ].eSrc, nModule := aForce[nJ].nModule,
                         nCh := aForce[nJ].nCh, nImgLo := aLo, nImgHi := aHi, nMod => nM, nIdx => nIdx);
    END_IF;
    IF eWhere = E_IoQ.Unused THEN
      eWhere := E_IoQ.NoModule;
    END_IF;
    IF F_IoForceSlot(stS := aForce[nJ], eWhere := eWhere, bPermit := bForcePermit,
                     bRelease := bReleaseAll OR NOT bBegun, tNow := tNow, tForceTime := tFt) THEN
      aForce[nJ].nRow := DINT_TO_INT(nIdx);
      IF eKind = E_IoKind.DigitalOut THEN
        aDoImg[nIdx].bQ := aForce[nJ].bQ;
        aDoImg[nIdx].bForced := TRUE;
      ELSE
        aAoImg[nIdx].fV := aForce[nJ].fV;
        aAoImg[nIdx].bForced := TRUE;
      END_IF;
      nForced := nForced + 1;
      IF aForce[nJ].tTimeLeft > tLeftMax THEN
        tLeftMax := aForce[nJ].tTimeLeft;
      END_IF;
    END_IF;
  END_IF;
END_FOR;

(* 4. the digital functions: bQ to the channel unless forced; bHoldOff beats both *)
nBad := 0;
nAddr := 0;
nShared := 0;
nNotFit := 0;
nMissFn := 0;
nChBad := 0;
dwFnBits := 0;
dwOkBits := 0;
dwHeldBits := 0;
FOR nI := 1 TO nD DO
  nSj := LOWER_BOUND(aDoSet, 1) + nI - 1;
  nJ := LOWER_BOUND(aDo, 1) + nI - 1;
  aDo[nJ].bOut := FALSE;
  eWhere := F_IoFind(aMods := aMods, eKind := E_IoKind.DigitalOut, eSrc := aDoSet[nSj].eSrc,
                     nModule := aDoSet[nSj].nModule, nCh := aDoSet[nSj].nCh, nImgLo := dLo, nImgHi := dHi,
                     nMod => nM, nIdx => nIdx);
  IF eWhere = E_IoQ.Ok THEN
    IF aDoImg[nIdx].nFn <> 0 THEN
      eWhere := E_IoQ.Shared;
    ELSE
      aMods[nM].nUsed := aMods[nM].nUsed + 1;
      aDoImg[nIdx].nFn := DINT_TO_USINT(MIN(nI, 255));
      IF NOT aMods[nM].bFitted THEN
        eWhere := E_IoQ.NotFitted;
      ELSIF NOT aMods[nM].bOk THEN
        eWhere := E_IoQ.Missing;
      ELSIF aDoImg[nIdx].bBad THEN
        eWhere := E_IoQ.Bad;
      END_IF;
      IF NOT aDoImg[nIdx].bForced THEN
        aDoImg[nIdx].bQ := aDo[nJ].bQ;
      END_IF;
      IF aDo[nJ].bHoldOff THEN
        aDoImg[nIdx].bQ := FALSE;
      END_IF;
      aDo[nJ].bOut := aDoImg[nIdx].bQ;
    END_IF;
  END_IF;
  aDo[nJ].bOk := eWhere = E_IoQ.Ok;
  aDo[nJ].bFit := eWhere <> E_IoQ.Unused AND eWhere <> E_IoQ.NotFitted;
  IF NOT aDo[nJ].bOk AND eWhere <> E_IoQ.Unused THEN
    nBad := nBad + 1;
  END_IF;
  CASE eWhere OF
    E_IoQ.NoModule, E_IoQ.NoChannel: nAddr := nAddr + 1;
    E_IoQ.Shared: nShared := nShared + 1;
    E_IoQ.NotFitted: nNotFit := nNotFit + 1;
    E_IoQ.Missing: nMissFn := nMissFn + 1;
    E_IoQ.Bad: nChBad := nChBad + 1;
  ELSE
    ;
  END_CASE;
  IF eWhere = E_IoQ.Ok OR eWhere = E_IoQ.NotFitted OR eWhere = E_IoQ.Missing OR eWhere = E_IoQ.Bad THEN
    IF aDoImg[nIdx].bForced THEN    // (nested: IEC AND does not short-circuit, idx is valid only here)
      IF aDo[nJ].bHoldOff THEN
        eWhere := E_IoQ.Blocked;
      ELSE
        eWhere := E_IoQ.Forced;
      END_IF;
    END_IF;
  END_IF;
  aDo[nJ].eWhy := eWhere;
  IF nI <= 32 THEN
    IF aDo[nJ].bQ THEN dwFnBits := dwFnBits OR SHL(DWORD#1, nI - 1); END_IF;
    IF aDo[nJ].bOk THEN dwOkBits := dwOkBits OR SHL(DWORD#1, nI - 1); END_IF;
    IF aDo[nJ].bHoldOff THEN dwHeldBits := dwHeldBits OR SHL(DWORD#1, nI - 1); END_IF;
  END_IF;
END_FOR;

(* 5. the analog functions *)
FOR nI := 1 TO nA DO
  nSj := LOWER_BOUND(aAoSet, 1) + nI - 1;
  nJ := LOWER_BOUND(aAo, 1) + nI - 1;
  aAo[nJ].fOut := 0.0;
  eWhere := F_IoFind(aMods := aMods, eKind := E_IoKind.AnalogOut, eSrc := aAoSet[nSj].eSrc,
                     nModule := aAoSet[nSj].nModule, nCh := aAoSet[nSj].nCh, nImgLo := aLo, nImgHi := aHi,
                     nMod => nM, nIdx => nIdx);
  IF eWhere = E_IoQ.Ok THEN
    IF aAoImg[nIdx].nFn <> 0 THEN
      eWhere := E_IoQ.Shared;
    ELSE
      aMods[nM].nUsed := aMods[nM].nUsed + 1;
      aAoImg[nIdx].nFn := DINT_TO_USINT(MIN(nI, 255));
      IF NOT aMods[nM].bFitted THEN
        eWhere := E_IoQ.NotFitted;
      ELSIF NOT aMods[nM].bOk THEN
        eWhere := E_IoQ.Missing;
      ELSIF aAoImg[nIdx].bBad THEN
        eWhere := E_IoQ.Bad;
      END_IF;
      IF NOT aAoImg[nIdx].bForced THEN
        aAoImg[nIdx].fV := aAo[nJ].fV;
      END_IF;
      aAo[nJ].fOut := aAoImg[nIdx].fV;
    END_IF;
  END_IF;
  aAo[nJ].bOk := eWhere = E_IoQ.Ok;
  aAo[nJ].bFit := eWhere <> E_IoQ.Unused AND eWhere <> E_IoQ.NotFitted;
  IF NOT aAo[nJ].bOk AND eWhere <> E_IoQ.Unused THEN
    nBad := nBad + 1;
  END_IF;
  CASE eWhere OF
    E_IoQ.NoModule, E_IoQ.NoChannel: nAddr := nAddr + 1;
    E_IoQ.Shared: nShared := nShared + 1;
    E_IoQ.NotFitted: nNotFit := nNotFit + 1;
    E_IoQ.Missing: nMissFn := nMissFn + 1;
    E_IoQ.Bad: nChBad := nChBad + 1;
  ELSE
    ;
  END_CASE;
  IF eWhere = E_IoQ.Ok OR eWhere = E_IoQ.NotFitted OR eWhere = E_IoQ.Missing OR eWhere = E_IoQ.Bad THEN
    IF aAoImg[nIdx].bForced THEN
      eWhere := E_IoQ.Forced;
    END_IF;
  END_IF;
  aAo[nJ].eWhy := eWhere;
END_FOR;

(* 6. the terminals for the IO page *)
dwTermBits := 0;
dwForcedBits := 0;
FOR nJ := dLo TO MIN(dHi, dLo + 31) DO
  IF aDoImg[nJ].bQ THEN dwTermBits := dwTermBits OR SHL(DWORD#1, nJ - dLo); END_IF;
  IF aDoImg[nJ].bForced THEN dwForcedBits := dwForcedBits OR SHL(DWORD#1, nJ - dLo); END_IF;
END_FOR;

(* 7. status *)
bBegun := TRUE;
bAnyForced := nForced > 0;
bConfigBad := bSizeBad OR nAddr > 0 OR nShared > 0 OR nNotFit > 0;
bAllOk := nBad = 0 AND nMissMod = 0;
refData.sts.nForced := nForced;
refData.sts.nBad := nBad;
refData.sts.nMissing := nMissMod;
refData.det.tForceLeft := tLeftMax;
bError := bConfigBad OR NOT bSetOk;
bWarning := NOT bError AND (nForced > 0 OR nMissMod > 0 OR nMissFn > 0 OR nChBad > 0 OR refData.sts.bRefused);
IF bSizeBad THEN
  eErrorId := E_UtError.IoArraySize;
ELSIF nAddr > 0 THEN
  eErrorId := E_UtError.IoAddress;
ELSIF nShared > 0 THEN
  eErrorId := E_UtError.IoShared;
ELSIF nNotFit > 0 THEN
  eErrorId := E_UtError.IoNotFitted;
ELSIF NOT bSetOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF nForced > 0 THEN
  eErrorId := E_UtError.IoForced;
ELSIF nMissMod > 0 OR nMissFn > 0 THEN
  eErrorId := E_UtError.IoMissing;
ELSIF nChBad > 0 THEN
  eErrorId := E_UtError.IoBad;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSE
  eState := E_State.Running;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK
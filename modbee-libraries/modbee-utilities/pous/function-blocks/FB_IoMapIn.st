(* FB_IoMapIn — the input side of the IO map: terminals to functions, from the rows (DESIGN-0.2.md section 5.6;
src-v2 UT_IO_MAP_IN). Call it FIRST in the scan, after your IO code has copied the hardware into the image,
before any logic.

Pins: bReleaseAll (TRUE releases every input force and refuses new ones: the HMI link lost, the "release all"
key), bUnusedOff (default TRUE: a function not fitted on this site, eSrc None, reads FALSE / 0.0; FALSE: it
reads its fail-safe), refData (set.tForceTime; counts) and the tables (VAR_IN_OUT, sized by the project):
aDiSet / aDi (digital input functions: rows / live), aAiSet / aAi (analog: rows / live, raw), aDiImg / aAiImg
(the terminals: your IO code writes bQ / fV and bBad), aMods (the module table, shared with FB_IoMapOut),
aForce (the force slots, shared with FB_IoMapOut; never retained)
-> bAllOk (every fitted function and fitted module is good), bAnyForced, bConfigBad (a wrong address, a function
on a module not fitted, tables that do not match or are longer than the kept copy), the IO page's bit words
dwTermBits / dwForcedBits (the first 32 digital terminals), dwFnBits / dwOkBits (the first 32 digital
functions: bQ, bOk), dwAnaOkBits (the first 32 analog functions: bOk), plus FB_Object's bError / bWarning /
eErrorId / eState.

For each function row it finds the channel (eSrc, nModule, nCh) through the module table and gives:
bQ / fV  the value. Digital: after the NC setting (bQ TRUE = active) and the debounce.
bOk      TRUE only when the value came from a good channel (or a force).
bFit     mapped on this site (eSrc not None, module fitted).
eWhy     Unused (eSrc None), NotFitted (its module not fitted), Missing (the module not answering), Bad (the
channel is stale / bad), NoModule / NoChannel (a wrong address), Forced, Ok.
A function that is not good reads its fail-safe value and bOk FALSE: your logic decides what a lost signal
means. When the channel comes back, bQ follows it at once (no debounce). An input channel may feed several
functions; the image row's nFn shows the first.
Forcing (commissioning): a slot names a channel (eKind DigitalIn or AnalogIn, eSrc, nModule, nCh) and the value; bCmdForce
starts it (again: starts its time again), bCmdRelease or bReleaseAll end it, it ends by itself after
set.tForceTime (1 ms .. 10 min, default 5 s), every force ends at power-up. The force goes on the terminal,
before NC and before scaling, as a test wire would; the debounce is skipped while forced. The image keeps the
real terminal value. A forced channel on a missing module reads good while forced.
Errors: bError for a configuration fault (IoArraySize, IoAddress, IoNotFitted) or rows that were never good
(BadSetting); bWarning for IoForced, IoMissing, IoBad, SettingRefused.

Kept settings (a retained last-good copy, restored at power-up, a bad write put back, sts.bRefused): the rows
are packed so each row is one retained value:
a digital row: one DWORD, bits 0..2 eSrc (None 0, Board 1, I2c 2, Field 3, Remote 4), 3..9 nModule (0..127),
10..17 nCh, 18 bNc, 19 bFailSafe, 20..31 tDebounce in 10 ms steps (0..40.95 s);
an analog row: ST_IoAiKept (the address DWORD as above, fFailSafe REAL);
plus set.tForceTime and the layout number. The first 32 digital and 8 analog rows are kept: 32 + 2 x 8 + 2 =
50 retained values. A row the packing cannot hold exactly (nModule over 127, a debounce over 40.95 s or not
in 10 ms steps, a fail-safe that is not a number, an unknown source) is a bad write and put back.
Forces stay in the maps (no separate FB_IoForce): a force is checked against the module table and the image
of its own direction, which each map already resolves; a separate block would need all four images and the
module lookups again. The slot logic is one shared function, F_IoForceSlot. *)

FUNCTION_BLOCK FB_IoMapIn EXTENDS FB_Object
  VAR_INPUT
    bReleaseAll : BOOL := FALSE; (* release every input force now and refuse new ones *)
    bUnusedOff : BOOL := TRUE; (* a function not fitted (eSrc None) reads FALSE / 0.0, not its fail-safe *)
    refData : REFERENCE TO ST_IoMapData;
  END_VAR
  VAR_IN_OUT
    aDiSet : ARRAY [*] OF ST_IODISET;
    aDi : ARRAY [*] OF ST_IODI;
    aAiSet : ARRAY [*] OF ST_IOAISET;
    aAi : ARRAY [*] OF ST_IOAI;
    aDiImg : ARRAY [*] OF ST_IODCH;
    aAiImg : ARRAY [*] OF ST_IOACH;
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
    dwAnaOkBits : DWORD;
  END_VAR
  VAR RETAIN
    aKeptDi : ARRAY [1..32] OF DWORD;
    aKeptAi : ARRAY [1..8] OF ST_IOAIKEPT;
    tKeptForceTime : TIME;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
    cDiKept : DINT := 32;
    cAiKept : DINT := 8;
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
    bR : BOOL;
    tFt : TIME;
    fFs : REAL;
    nDw : DWORD;
    nDeb : DINT;
    eSrc : E_IoSrc;
    nMod : USINT;
    nCh : USINT;
    bX : BOOL;
    nForced : INT;
    nBad : INT;
    nAddr : INT;
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
bSizeBad := UPPER_BOUND(aDiSet, 1) - LOWER_BOUND(aDiSet, 1) <> UPPER_BOUND(aDi, 1) - LOWER_BOUND(aDi, 1)
            OR UPPER_BOUND(aAiSet, 1) - LOWER_BOUND(aAiSet, 1) <> UPPER_BOUND(aAi, 1) - LOWER_BOUND(aAi, 1);
nD := MIN(UPPER_BOUND(aDiSet, 1) - LOWER_BOUND(aDiSet, 1), UPPER_BOUND(aDi, 1) - LOWER_BOUND(aDi, 1)) + 1;
nA := MIN(UPPER_BOUND(aAiSet, 1) - LOWER_BOUND(aAiSet, 1), UPPER_BOUND(aAi, 1) - LOWER_BOUND(aAi, 1)) + 1;
bSizeBad := bSizeBad OR nD > cDiKept OR nA > cAiKept;

IF refData.bCmdReset THEN
  refData.bCmdReset := FALSE;
  refData.sts.bRefused := FALSE;
END_IF;

(* 0. the rows: the kept copy at power-up, a bad write put back *)
bRestore := bFirstScan AND nKeptLayout = cLayout;
IF NOT bRestore THEN
  bSetOk := refData.set.tForceTime >= T#1ms AND refData.set.tForceTime <= T#10m;
  FOR nI := 1 TO nD DO
    nSj := LOWER_BOUND(aDiSet, 1) + nI - 1;
    nDeb := TIME_TO_DINT(aDiSet[nSj].tDebounce);
    IF NOT F_IoAddrOk(eSrc := aDiSet[nSj].eSrc, nModule := aDiSet[nSj].nModule)
       OR nDeb < 0 OR nDeb > 40950 OR nDeb MOD 10 <> 0 THEN
      bSetOk := FALSE;
    END_IF;
  END_FOR;
  FOR nI := 1 TO nA DO
    nSj := LOWER_BOUND(aAiSet, 1) + nI - 1;
    fFs := aAiSet[nSj].fFailSafe;
    IF NOT F_IoAddrOk(eSrc := aAiSet[nSj].eSrc, nModule := aAiSet[nSj].nModule) OR NOT (ABS(fFs) <= REAL#3.4E38) THEN
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
  FOR nI := 1 TO MIN(nD, cDiKept) DO
    nSj := LOWER_BOUND(aDiSet, 1) + nI - 1;
    nDw := aKeptDi[nI];
    bX := F_IoAddrUnpack(dwAddr := nDw, eSrc => eSrc, nModule => nMod, nCh => nCh);
    aDiSet[nSj].eSrc := eSrc;
    aDiSet[nSj].nModule := nMod;
    aDiSet[nSj].nCh := nCh;
    aDiSet[nSj].bNc := (nDw AND DWORD#16#40000) <> 0;
    aDiSet[nSj].bFailSafe := (nDw AND DWORD#16#80000) <> 0;
    aDiSet[nSj].tDebounce := DINT_TO_TIME(DWORD_TO_DINT(SHR(nDw, 20) AND DWORD#16#FFF) * 10);
  END_FOR;
  FOR nI := 1 TO MIN(nA, cAiKept) DO
    nSj := LOWER_BOUND(aAiSet, 1) + nI - 1;
    bX := F_IoAddrUnpack(dwAddr := aKeptAi[nI].dwAddr, eSrc => eSrc, nModule => nMod, nCh => nCh);
    aAiSet[nSj].eSrc := eSrc;
    aAiSet[nSj].nModule := nMod;
    aAiSet[nSj].nCh := nCh;
    aAiSet[nSj].fFailSafe := aKeptAi[nI].fFailSafe;
  END_FOR;
  bSetOk := TRUE;                 // only good rows are ever kept
END_IF;
IF bSetOk THEN
  tKeptForceTime := refData.set.tForceTime;
  FOR nI := 1 TO MIN(nD, cDiKept) DO
    nSj := LOWER_BOUND(aDiSet, 1) + nI - 1;
    nDw := F_IoAddrPack(eSrc := aDiSet[nSj].eSrc, nModule := aDiSet[nSj].nModule, nCh := aDiSet[nSj].nCh)
          OR SHL(DINT_TO_DWORD(TIME_TO_DINT(aDiSet[nSj].tDebounce) / 10), 20);
    IF aDiSet[nSj].bNc THEN nDw := nDw OR DWORD#16#40000; END_IF;
    IF aDiSet[nSj].bFailSafe THEN nDw := nDw OR DWORD#16#80000; END_IF;
    aKeptDi[nI] := nDw;
  END_FOR;
  FOR nI := 1 TO MIN(nA, cAiKept) DO
    nSj := LOWER_BOUND(aAiSet, 1) + nI - 1;
    aKeptAi[nI].dwAddr := F_IoAddrPack(eSrc := aAiSet[nSj].eSrc, nModule := aAiSet[nSj].nModule,
                                        nCh := aAiSet[nSj].nCh);
    aKeptAi[nI].fFailSafe := aAiSet[nSj].fFailSafe;
  END_FOR;
  nKeptLayout := cLayout;
END_IF;
tFt := refData.set.tForceTime;
IF tFt <= T#0s THEN
  tFt := T#5s;
ELSIF tFt > T#10m THEN
  tFt := T#10m;
END_IF;
dLo := LOWER_BOUND(aDiImg, 1);
dHi := UPPER_BOUND(aDiImg, 1);
aLo := LOWER_BOUND(aAiImg, 1);
aHi := UPPER_BOUND(aAiImg, 1);

(* 1. the image: nothing forced yet this scan *)
FOR nJ := dLo TO dHi DO
  aDiImg[nJ].bForced := FALSE;
  aDiImg[nJ].nFn := 0;
END_FOR;
FOR nJ := aLo TO aHi DO
  aAiImg[nJ].bForced := FALSE;
  aAiImg[nJ].nFn := 0;
END_FOR;

(* 2. the input modules *)
nMissMod := 0;
FOR nK := LOWER_BOUND(aMods, 1) TO UPPER_BOUND(aMods, 1) DO
  IF aMods[nK].eKind = E_IoKind.DigitalIn OR aMods[nK].eKind = E_IoKind.AnalogIn THEN
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

(* 3. the force slots for inputs: mark the forced terminals (the functions take the forced value) *)
nForced := 0;
tLeftMax := T#0s;
FOR nJ := LOWER_BOUND(aForce, 1) TO UPPER_BOUND(aForce, 1) DO
  eKind := aForce[nJ].eKind;
  IF eKind = E_IoKind.None THEN
    aForce[nJ].bActive := FALSE;
    aForce[nJ].eState := E_IoQ.Unused;
    aForce[nJ].tTimeLeft := T#0s;
    aForce[nJ].bForceSeen := aForce[nJ].bCmdForce;
    aForce[nJ].bReleaseSeen := aForce[nJ].bCmdRelease;
    aForce[nJ].bCmdForce := FALSE;
    aForce[nJ].bCmdRelease := FALSE;
  ELSIF eKind = E_IoKind.DigitalIn OR eKind = E_IoKind.AnalogIn THEN
    IF eKind = E_IoKind.DigitalIn THEN
      eWhere := F_IoFind(aMods := aMods, eKind := eKind, eSrc := aForce[nJ].eSrc, nModule := aForce[nJ].nModule,
                         nCh := aForce[nJ].nCh, nImgLo := dLo, nImgHi := dHi, nMod => nM, nIdx => nIdx);
    ELSE
      eWhere := F_IoFind(aMods := aMods, eKind := eKind, eSrc := aForce[nJ].eSrc, nModule := aForce[nJ].nModule,
                         nCh := aForce[nJ].nCh, nImgLo := aLo, nImgHi := aHi, nMod => nM, nIdx => nIdx);
    END_IF;
    IF eWhere = E_IoQ.Unused THEN
      eWhere := E_IoQ.NoModule;
    END_IF;
    IF F_IoForceSlot(stS := aForce[nJ], eWhere := eWhere, bPermit := TRUE, bRelease := bReleaseAll OR NOT bBegun,
                     tNow := tNow, tForceTime := tFt) THEN
      aForce[nJ].nRow := DINT_TO_INT(nIdx);
      IF eKind = E_IoKind.DigitalIn THEN
        aDiImg[nIdx].bForced := TRUE;
      ELSE
        aAiImg[nIdx].bForced := TRUE;
      END_IF;
      nForced := nForced + 1;
      IF aForce[nJ].tTimeLeft > tLeftMax THEN
        tLeftMax := aForce[nJ].tTimeLeft;
      END_IF;
    END_IF;
  END_IF;
END_FOR;

(* 4. the digital input functions *)
nBad := 0;
nAddr := 0;
nNotFit := 0;
nMissFn := 0;
nChBad := 0;
dwFnBits := 0;
dwOkBits := 0;
FOR nI := 1 TO nD DO
  nSj := LOWER_BOUND(aDiSet, 1) + nI - 1;
  nJ := LOWER_BOUND(aDi, 1) + nI - 1;
  eWhere := F_IoFind(aMods := aMods, eKind := E_IoKind.DigitalIn, eSrc := aDiSet[nSj].eSrc,
                     nModule := aDiSet[nSj].nModule, nCh := aDiSet[nSj].nCh, nImgLo := dLo, nImgHi := dHi,
                     nMod => nM, nIdx => nIdx);
  IF eWhere = E_IoQ.Ok THEN
    aMods[nM].nUsed := aMods[nM].nUsed + 1;
    IF aDiImg[nIdx].nFn = 0 AND nI <= 255 THEN
      aDiImg[nIdx].nFn := DINT_TO_USINT(nI);
    END_IF;
    IF aDiImg[nIdx].bForced THEN
      eWhere := E_IoQ.Forced;
    ELSIF NOT aMods[nM].bFitted THEN
      eWhere := E_IoQ.NotFitted;
    ELSIF NOT aMods[nM].bOk THEN
      eWhere := E_IoQ.Missing;
    ELSIF aDiImg[nIdx].bBad THEN
      eWhere := E_IoQ.Bad;
    END_IF;
  END_IF;
  IF eWhere = E_IoQ.Ok OR eWhere = E_IoQ.Forced THEN
    bR := aDiImg[nIdx].bQ;
    IF eWhere = E_IoQ.Forced THEN
      FOR nK := LOWER_BOUND(aForce, 1) TO UPPER_BOUND(aForce, 1) DO
        IF aForce[nK].bActive AND aForce[nK].eKind = E_IoKind.DigitalIn AND INT_TO_DINT(aForce[nK].nRow) = nIdx THEN
          bR := aForce[nK].bQ;
        END_IF;
      END_FOR;
    END_IF;
    bR := bR XOR aDiSet[nSj].bNc;
    IF eWhere = E_IoQ.Forced OR NOT aDi[nJ].bOk THEN
      aDi[nJ].bQ := bR;            // forced, or the channel just came back: no debounce
      aDi[nJ].bRaw := bR;
      aDi[nJ].tRawAt := tNow;
    ELSE
      IF bR <> aDi[nJ].bRaw THEN
        aDi[nJ].bRaw := bR;
        aDi[nJ].tRawAt := tNow;
      END_IF;
      IF tNow - aDi[nJ].tRawAt >= aDiSet[nSj].tDebounce THEN
        aDi[nJ].bQ := aDi[nJ].bRaw;
      END_IF;
    END_IF;
    aDi[nJ].bOk := TRUE;
  ELSIF eWhere = E_IoQ.Unused AND bUnusedOff THEN
    aDi[nJ].bQ := FALSE;           // not fitted on this site: not active
    aDi[nJ].bOk := FALSE;
  ELSE
    aDi[nJ].bQ := aDiSet[nSj].bFailSafe;
    aDi[nJ].bOk := FALSE;
    IF eWhere <> E_IoQ.Unused THEN
      nBad := nBad + 1;
    END_IF;
  END_IF;
  aDi[nJ].eWhy := eWhere;
  aDi[nJ].bFit := eWhere <> E_IoQ.Unused AND eWhere <> E_IoQ.NotFitted;
  CASE eWhere OF
    E_IoQ.NoModule, E_IoQ.NoChannel: nAddr := nAddr + 1;
    E_IoQ.NotFitted: nNotFit := nNotFit + 1;
    E_IoQ.Missing: nMissFn := nMissFn + 1;
    E_IoQ.Bad: nChBad := nChBad + 1;
  ELSE
    ;
  END_CASE;
  IF nI <= 32 THEN
    IF aDi[nJ].bQ THEN dwFnBits := dwFnBits OR SHL(DWORD#1, nI - 1); END_IF;
    IF aDi[nJ].bOk THEN dwOkBits := dwOkBits OR SHL(DWORD#1, nI - 1); END_IF;
  END_IF;
END_FOR;

(* 5. the analog input functions *)
dwAnaOkBits := 0;
FOR nI := 1 TO nA DO
  nSj := LOWER_BOUND(aAiSet, 1) + nI - 1;
  nJ := LOWER_BOUND(aAi, 1) + nI - 1;
  eWhere := F_IoFind(aMods := aMods, eKind := E_IoKind.AnalogIn, eSrc := aAiSet[nSj].eSrc,
                     nModule := aAiSet[nSj].nModule, nCh := aAiSet[nSj].nCh, nImgLo := aLo, nImgHi := aHi,
                     nMod => nM, nIdx => nIdx);
  IF eWhere = E_IoQ.Ok THEN
    aMods[nM].nUsed := aMods[nM].nUsed + 1;
    IF aAiImg[nIdx].nFn = 0 AND nI <= 255 THEN
      aAiImg[nIdx].nFn := DINT_TO_USINT(nI);
    END_IF;
    IF aAiImg[nIdx].bForced THEN
      eWhere := E_IoQ.Forced;
    ELSIF NOT aMods[nM].bFitted THEN
      eWhere := E_IoQ.NotFitted;
    ELSIF NOT aMods[nM].bOk THEN
      eWhere := E_IoQ.Missing;
    ELSIF aAiImg[nIdx].bBad THEN
      eWhere := E_IoQ.Bad;
    END_IF;
  END_IF;
  IF eWhere = E_IoQ.Ok OR eWhere = E_IoQ.Forced THEN
    aAi[nJ].fV := aAiImg[nIdx].fV;
    IF eWhere = E_IoQ.Forced THEN
      FOR nK := LOWER_BOUND(aForce, 1) TO UPPER_BOUND(aForce, 1) DO
        IF aForce[nK].bActive AND aForce[nK].eKind = E_IoKind.AnalogIn AND INT_TO_DINT(aForce[nK].nRow) = nIdx THEN
          aAi[nJ].fV := aForce[nK].fV;
        END_IF;
      END_FOR;
    END_IF;
    aAi[nJ].bOk := TRUE;
  ELSIF eWhere = E_IoQ.Unused AND bUnusedOff THEN
    aAi[nJ].fV := 0.0;
    aAi[nJ].bOk := FALSE;
  ELSE
    fFs := aAiSet[nSj].fFailSafe;
    IF NOT (ABS(fFs) <= REAL#3.4E38) THEN
      fFs := 0.0;
    END_IF;
    aAi[nJ].fV := fFs;
    aAi[nJ].bOk := FALSE;
    IF eWhere <> E_IoQ.Unused THEN
      nBad := nBad + 1;
    END_IF;
  END_IF;
  aAi[nJ].eWhy := eWhere;
  aAi[nJ].bFit := eWhere <> E_IoQ.Unused AND eWhere <> E_IoQ.NotFitted;
  CASE eWhere OF
    E_IoQ.NoModule, E_IoQ.NoChannel: nAddr := nAddr + 1;
    E_IoQ.NotFitted: nNotFit := nNotFit + 1;
    E_IoQ.Missing: nMissFn := nMissFn + 1;
    E_IoQ.Bad: nChBad := nChBad + 1;
  ELSE
    ;
  END_CASE;
  IF nI <= 32 AND aAi[nJ].bOk THEN
    dwAnaOkBits := dwAnaOkBits OR SHL(DWORD#1, nI - 1);
  END_IF;
END_FOR;

(* 6. the terminals for the IO page *)
dwTermBits := 0;
dwForcedBits := 0;
FOR nJ := dLo TO MIN(dHi, dLo + 31) DO
  IF aDiImg[nJ].bQ THEN dwTermBits := dwTermBits OR SHL(DWORD#1, nJ - dLo); END_IF;
  IF aDiImg[nJ].bForced THEN dwForcedBits := dwForcedBits OR SHL(DWORD#1, nJ - dLo); END_IF;
END_FOR;

(* 7. status *)
bBegun := TRUE;
bAnyForced := nForced > 0;
bConfigBad := bSizeBad OR nAddr > 0 OR nNotFit > 0;
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
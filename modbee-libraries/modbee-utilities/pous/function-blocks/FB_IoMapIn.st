(* FB_IoMapIn — the input side of the IO map: terminals to functions, from the rows. Call it FIRST in the scan, after
your IO code has copied the hardware into the image, before any logic.

Pins: bReleaseAllForces (TRUE releases every input force and refuses new ones: the HMI link lost, the "release all"
key), bUnfittedReadsOff (default TRUE: a function not fitted on this site, eSource None, reads FALSE / 0.0; FALSE: it
reads its fail-safe), refData (set.tForceTime; counts) and the tables (VAR_IN_OUT, sized by the project):
aDigitalInSettings / aDigitalIns (digital input functions: rows / live), aAnalogInSettings / aAnalogIns (analog: rows / live, raw), aDigitalInTerminals / aAnalogInTerminals
(the terminals: your IO code writes bTerminal / fRawValue and bChannelBad), aModules (the module table, shared with FB_IoMapOut),
aForces (the force slots, shared with FB_IoMapOut; never retained)
-> bAllGood (every fitted function and fitted module is good), bAnyForced, bMapSettingBad (a wrong address, a function
on a module not fitted, tables that do not match or are longer than the kept copy), the IO page's bit words
nTerminalBits / nForcedBits (the first 32 digital terminals), nFunctionBits / nGoodBits (the first 32 digital
functions: bActive, bGood), nAnalogGoodBits (the first 32 analog functions: bGood), plus FB_Object's bError / bWarning /
eErrorId / eState.

For each function row it finds the channel (eSource, nModuleNumber, nChannel) through the module table and gives:
bActive / fRawValue  the value. Digital: after the NC setting (bActive TRUE = active) and the debounce.
bGood      TRUE only when the value came from a good channel (or a force).
bFitted     mapped on this site (eSource not None, module fitted).
eQuality     Unused (eSource None), NotFitted (its module not fitted), Missing (the module not answering), Bad (the
channel is stale / bad), NoModule / NoChannel (a wrong address), Forced, Ok.
A function that is not good reads its fail-safe value and bGood FALSE: your logic decides what a lost signal
means. When the channel comes back, bActive follows it at once (no debounce). An input channel may feed several
functions; the image row's nFunctionRow shows the first.
Forcing (commissioning): a slot names a channel (eKind DigitalIn or AnalogIn, eSource, nModuleNumber, nChannel) and the value; bCmdForceNow
starts it (again: starts its time again), bCmdReleaseNow or bReleaseAllForces end it, it ends by itself after
set.tForceTime (1 ms .. 10 min, default 5 s), every force ends at power-up. The force goes on the terminal,
before NC and before scaling, as a test wire would; the debounce is skipped while forced. The image keeps the
real terminal value. A forced channel on a missing module reads good while forced.
Errors: bError for a configuration fault (IoArraySize, IoAddress, IoNotFitted) or rows that were never good
(BadSetting); bWarning for IoForced, IoMissing, IoBad, SettingRefused.

Kept settings (a retained last-good copy, restored at power-up, a bad write put back, sts.bSettingRefused / eSettingRefusedErrorId):
the rows
are packed so each row is one retained value:
a digital row: one DWORD, bits 0..2 eSource (None 0, Board 1, I2c 2, Field 3, Remote 4), 3..9 nModuleNumber (0..127),
10..17 nChannel, 18 bNormallyClosed, 19 bFailSafeState, 20..31 tDebounceTime in 10 ms steps (0..40.95 s);
an analog row: ST_IoAiKept (the address DWORD as above, fFailSafeValue REAL);
plus set.tForceTime and the layout number. The first 32 digital and 8 analog rows are kept: 32 + 2 x 8 + 2 =
50 retained values. A row the packing cannot hold exactly (nModuleNumber over 127, a debounce over 40.95 s or not
in 10 ms steps, a fail-safe that is not a number, an unknown source) is a bad write and put back.
Forces stay in the maps (no separate FB_IoForce): a force is checked against the module table and the image
of its own direction, which each map already resolves; a separate block would need all four images and the
module lookups again. The slot logic is one shared function, F_IoForceSlot. *)

FUNCTION_BLOCK FB_IoMapIn EXTENDS FB_Object
  VAR_INPUT
    bReleaseAllForces : BOOL := FALSE; (* release every input force now and refuse new ones *)
    bUnfittedReadsOff : BOOL := TRUE; (* a function not fitted (eSource None) reads FALSE / 0.0, not its fail-safe *)
    refData : REFERENCE TO ST_IoMapData; (* the map's record: force time, counts *)
  END_VAR
  VAR_IN_OUT
    aDigitalInSettings : ARRAY [*] OF ST_IODISET; (* digital input functions: one settings row each *)
    aDigitalIns : ARRAY [*] OF ST_IODI; (* digital input functions: the live rows *)
    aAnalogInSettings : ARRAY [*] OF ST_IOAISET; (* analog input functions: one settings row each *)
    aAnalogIns : ARRAY [*] OF ST_IOAI; (* analog input functions: the live rows (raw) *)
    aDigitalInTerminals : ARRAY [*] OF ST_IODCH; (* the digital terminals: your IO code writes bTerminal and bChannelBad *)
    aAnalogInTerminals : ARRAY [*] OF ST_IOACH; (* the analog terminals: your IO code writes fRawValue and bChannelBad *)
    aModules : ARRAY [*] OF ST_IOMODULE; (* the module table, shared by FB_IoMapIn and FB_IoMapOut *)
    aForces : ARRAY [*] OF ST_IOFORCE; (* the force slots, shared; never retained *)
  END_VAR
  VAR_OUTPUT
    bAllGood : BOOL; (* every fitted function and fitted module is good *)
    bAnyForced : BOOL; (* a force is on *)
    bMapSettingBad : BOOL; (* a wrong address, a function on a module not fitted, or tables that do not match *)
    nTerminalBits : DWORD; (* the first 32 digital terminals, a bit each *)
    nFunctionBits : DWORD; (* the first 32 digital functions' bActive, a bit each *)
    nGoodBits : DWORD; (* the first 32 digital functions' bGood, a bit each *)
    nForcedBits : DWORD; (* the first 32 digital terminals forced, a bit each *)
    nAnalogGoodBits : DWORD; (* the first 32 analog functions' bGood, a bit each *)
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
    eWhy : E_UtError; (* the first bad setting of this write *)
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
  bAllGood := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
bSizeBad := UPPER_BOUND(aDigitalInSettings, 1) - LOWER_BOUND(aDigitalInSettings, 1) <> UPPER_BOUND(aDigitalIns, 1) - LOWER_BOUND(aDigitalIns, 1)
            OR UPPER_BOUND(aAnalogInSettings, 1) - LOWER_BOUND(aAnalogInSettings, 1) <> UPPER_BOUND(aAnalogIns, 1) - LOWER_BOUND(aAnalogIns, 1);
nD := MIN(UPPER_BOUND(aDigitalInSettings, 1) - LOWER_BOUND(aDigitalInSettings, 1), UPPER_BOUND(aDigitalIns, 1) - LOWER_BOUND(aDigitalIns, 1)) + 1;
nA := MIN(UPPER_BOUND(aAnalogInSettings, 1) - LOWER_BOUND(aAnalogInSettings, 1), UPPER_BOUND(aAnalogIns, 1) - LOWER_BOUND(aAnalogIns, 1)) + 1;
bSizeBad := bSizeBad OR nD > cDiKept OR nA > cAiKept;

IF refData.bCmdClearRefused THEN
  refData.bCmdClearRefused := FALSE;
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

(* 0. the rows: the kept copy at power-up, a bad write put back *)
bRestore := bFirstScan AND nKeptLayout = cLayout;
IF NOT bRestore THEN
  bSetOk := refData.set.tForceTime >= T#1ms AND refData.set.tForceTime <= T#10m;
  eWhy := E_UtError.None;
  IF NOT bSetOk THEN
    eWhy := E_UtError.TimeBad;
  END_IF;
  FOR nI := 1 TO nD DO
    nSj := LOWER_BOUND(aDigitalInSettings, 1) + nI - 1;
    nDeb := TIME_TO_DINT(aDigitalInSettings[nSj].tDebounceTime);
    IF NOT F_IoAddrOk(eSource := aDigitalInSettings[nSj].eSource, nModuleNumber := aDigitalInSettings[nSj].nModuleNumber) THEN
      bSetOk := FALSE;
      IF eWhy = E_UtError.None THEN eWhy := E_UtError.IoAddress; END_IF;
    ELSIF nDeb < 0 OR nDeb > 40950 OR nDeb MOD 10 <> 0 THEN
      bSetOk := FALSE;
      IF eWhy = E_UtError.None THEN eWhy := E_UtError.TimeBad; END_IF;
    END_IF;
  END_FOR;
  FOR nI := 1 TO nA DO
    nSj := LOWER_BOUND(aAnalogInSettings, 1) + nI - 1;
    fFs := aAnalogInSettings[nSj].fFailSafeValue;
    IF NOT F_IoAddrOk(eSource := aAnalogInSettings[nSj].eSource, nModuleNumber := aAnalogInSettings[nSj].nModuleNumber) THEN
      bSetOk := FALSE;
      IF eWhy = E_UtError.None THEN eWhy := E_UtError.IoAddress; END_IF;
    ELSIF NOT (ABS(fFs) <= REAL#3.4E38) THEN
      bSetOk := FALSE;
      IF eWhy = E_UtError.None THEN eWhy := E_UtError.ValueBad; END_IF;
    END_IF;
  END_FOR;
  IF NOT bSetOk AND nKeptLayout = cLayout THEN
    bRestore := TRUE;
    refData.sts.bSettingRefused := TRUE;
    refData.sts.eSettingRefusedErrorId := eWhy;
  END_IF;
END_IF;
IF bRestore THEN
  refData.set.tForceTime := tKeptForceTime;
  FOR nI := 1 TO MIN(nD, cDiKept) DO
    nSj := LOWER_BOUND(aDigitalInSettings, 1) + nI - 1;
    nDw := aKeptDi[nI];
    bX := F_IoAddrUnpack(nPackedAddress := nDw, eSource => eSrc, nModuleNumber => nMod, nChannel => nCh);
    aDigitalInSettings[nSj].eSource := eSrc;
    aDigitalInSettings[nSj].nModuleNumber := nMod;
    aDigitalInSettings[nSj].nChannel := nCh;
    aDigitalInSettings[nSj].bNormallyClosed := (nDw AND DWORD#16#40000) <> 0;
    aDigitalInSettings[nSj].bFailSafeState := (nDw AND DWORD#16#80000) <> 0;
    aDigitalInSettings[nSj].tDebounceTime := DINT_TO_TIME(DWORD_TO_DINT(SHR(nDw, 20) AND DWORD#16#FFF) * 10);
  END_FOR;
  FOR nI := 1 TO MIN(nA, cAiKept) DO
    nSj := LOWER_BOUND(aAnalogInSettings, 1) + nI - 1;
    bX := F_IoAddrUnpack(nPackedAddress := aKeptAi[nI].nPackedAddress, eSource => eSrc, nModuleNumber => nMod, nChannel => nCh);
    aAnalogInSettings[nSj].eSource := eSrc;
    aAnalogInSettings[nSj].nModuleNumber := nMod;
    aAnalogInSettings[nSj].nChannel := nCh;
    aAnalogInSettings[nSj].fFailSafeValue := aKeptAi[nI].fFailSafeValue;
  END_FOR;
  bSetOk := TRUE;                 // only good rows are ever kept
END_IF;
IF bSetOk THEN
  tKeptForceTime := refData.set.tForceTime;
  FOR nI := 1 TO MIN(nD, cDiKept) DO
    nSj := LOWER_BOUND(aDigitalInSettings, 1) + nI - 1;
    nDw := F_IoAddrPack(eSource := aDigitalInSettings[nSj].eSource, nModuleNumber := aDigitalInSettings[nSj].nModuleNumber, nChannel := aDigitalInSettings[nSj].nChannel)
          OR SHL(DINT_TO_DWORD(TIME_TO_DINT(aDigitalInSettings[nSj].tDebounceTime) / 10), 20);
    IF aDigitalInSettings[nSj].bNormallyClosed THEN nDw := nDw OR DWORD#16#40000; END_IF;
    IF aDigitalInSettings[nSj].bFailSafeState THEN nDw := nDw OR DWORD#16#80000; END_IF;
    aKeptDi[nI] := nDw;
  END_FOR;
  FOR nI := 1 TO MIN(nA, cAiKept) DO
    nSj := LOWER_BOUND(aAnalogInSettings, 1) + nI - 1;
    aKeptAi[nI].nPackedAddress := F_IoAddrPack(eSource := aAnalogInSettings[nSj].eSource, nModuleNumber := aAnalogInSettings[nSj].nModuleNumber,
                                        nChannel := aAnalogInSettings[nSj].nChannel);
    aKeptAi[nI].fFailSafeValue := aAnalogInSettings[nSj].fFailSafeValue;
  END_FOR;
  nKeptLayout := cLayout;
END_IF;
tFt := refData.set.tForceTime;
IF tFt <= T#0s THEN
  tFt := T#5s;
ELSIF tFt > T#10m THEN
  tFt := T#10m;
END_IF;
dLo := LOWER_BOUND(aDigitalInTerminals, 1);
dHi := UPPER_BOUND(aDigitalInTerminals, 1);
aLo := LOWER_BOUND(aAnalogInTerminals, 1);
aHi := UPPER_BOUND(aAnalogInTerminals, 1);

(* 1. the image: nothing forced yet this scan *)
FOR nJ := dLo TO dHi DO
  aDigitalInTerminals[nJ].bForced := FALSE;
  aDigitalInTerminals[nJ].nFunctionRow := 0;
END_FOR;
FOR nJ := aLo TO aHi DO
  aAnalogInTerminals[nJ].bForced := FALSE;
  aAnalogInTerminals[nJ].nFunctionRow := 0;
END_FOR;

(* 2. the input modules *)
nMissMod := 0;
FOR nK := LOWER_BOUND(aModules, 1) TO UPPER_BOUND(aModules, 1) DO
  IF aModules[nK].eChannelKind = E_IoKind.DigitalIn OR aModules[nK].eChannelKind = E_IoKind.AnalogIn THEN
    aModules[nK].nFunctionsMapped := 0;
    IF NOT aModules[nK].bModuleFitted THEN
      aModules[nK].eModuleState := E_IoQ.NotFitted;
    ELSIF NOT aModules[nK].bAnswering THEN
      aModules[nK].eModuleState := E_IoQ.Missing;
      nMissMod := nMissMod + 1;
    ELSE
      aModules[nK].eModuleState := E_IoQ.Ok;
    END_IF;
  END_IF;
END_FOR;

(* 3. the force slots for inputs: mark the forced terminals (the functions take the forced value) *)
nForced := 0;
tLeftMax := T#0s;
FOR nJ := LOWER_BOUND(aForces, 1) TO UPPER_BOUND(aForces, 1) DO
  eKind := aForces[nJ].eChannelKind;
  IF eKind = E_IoKind.None THEN
    aForces[nJ].bForcing := FALSE;
    aForces[nJ].eForceState := E_IoQ.Unused;
    aForces[nJ].tTimeLeft := T#0s;
    aForces[nJ].bForceCommandTaken := aForces[nJ].bCmdForceNow;
    aForces[nJ].bReleaseCommandTaken := aForces[nJ].bCmdReleaseNow;
    aForces[nJ].bCmdForceNow := FALSE;
    aForces[nJ].bCmdReleaseNow := FALSE;
  ELSIF eKind = E_IoKind.DigitalIn OR eKind = E_IoKind.AnalogIn THEN
    IF eKind = E_IoKind.DigitalIn THEN
      eWhere := F_IoFind(aModules := aModules, eChannelKind := eKind, eSource := aForces[nJ].eSource, nModuleNumber := aForces[nJ].nModuleNumber,
                         nChannel := aForces[nJ].nChannel, nImageFirstRow := dLo, nImageLastRow := dHi, nModuleRow => nM, nImageRow => nIdx);
    ELSE
      eWhere := F_IoFind(aModules := aModules, eChannelKind := eKind, eSource := aForces[nJ].eSource, nModuleNumber := aForces[nJ].nModuleNumber,
                         nChannel := aForces[nJ].nChannel, nImageFirstRow := aLo, nImageLastRow := aHi, nModuleRow => nM, nImageRow => nIdx);
    END_IF;
    IF eWhere = E_IoQ.Unused THEN
      eWhere := E_IoQ.NoModule;
    END_IF;
    IF F_IoForceSlot(stForceSlot := aForces[nJ], eAddressQuality := eWhere, bForcingAllowed := TRUE, bReleaseAllForces := bReleaseAllForces OR NOT bBegun,
                     tNow := tNow, tForceTime := tFt) THEN
      aForces[nJ].nImageRow := DINT_TO_INT(nIdx);
      IF eKind = E_IoKind.DigitalIn THEN
        aDigitalInTerminals[nIdx].bForced := TRUE;
      ELSE
        aAnalogInTerminals[nIdx].bForced := TRUE;
      END_IF;
      nForced := nForced + 1;
      IF aForces[nJ].tTimeLeft > tLeftMax THEN
        tLeftMax := aForces[nJ].tTimeLeft;
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
nFunctionBits := 0;
nGoodBits := 0;
FOR nI := 1 TO nD DO
  nSj := LOWER_BOUND(aDigitalInSettings, 1) + nI - 1;
  nJ := LOWER_BOUND(aDigitalIns, 1) + nI - 1;
  eWhere := F_IoFind(aModules := aModules, eChannelKind := E_IoKind.DigitalIn, eSource := aDigitalInSettings[nSj].eSource,
                     nModuleNumber := aDigitalInSettings[nSj].nModuleNumber, nChannel := aDigitalInSettings[nSj].nChannel, nImageFirstRow := dLo, nImageLastRow := dHi,
                     nModuleRow => nM, nImageRow => nIdx);
  IF eWhere = E_IoQ.Ok THEN
    aModules[nM].nFunctionsMapped := aModules[nM].nFunctionsMapped + 1;
    IF aDigitalInTerminals[nIdx].nFunctionRow = 0 AND nI <= 255 THEN
      aDigitalInTerminals[nIdx].nFunctionRow := DINT_TO_USINT(nI);
    END_IF;
    IF aDigitalInTerminals[nIdx].bForced THEN
      eWhere := E_IoQ.Forced;
    ELSIF NOT aModules[nM].bModuleFitted THEN
      eWhere := E_IoQ.NotFitted;
    ELSIF NOT aModules[nM].bAnswering THEN
      eWhere := E_IoQ.Missing;
    ELSIF aDigitalInTerminals[nIdx].bChannelBad THEN
      eWhere := E_IoQ.Bad;
    END_IF;
  END_IF;
  IF eWhere = E_IoQ.Ok OR eWhere = E_IoQ.Forced THEN
    bR := aDigitalInTerminals[nIdx].bTerminal;
    IF eWhere = E_IoQ.Forced THEN
      FOR nK := LOWER_BOUND(aForces, 1) TO UPPER_BOUND(aForces, 1) DO
        IF aForces[nK].bForcing AND aForces[nK].eChannelKind = E_IoKind.DigitalIn AND INT_TO_DINT(aForces[nK].nImageRow) = nIdx THEN
          bR := aForces[nK].bForceState;
        END_IF;
      END_FOR;
    END_IF;
    bR := bR XOR aDigitalInSettings[nSj].bNormallyClosed;
    IF eWhere = E_IoQ.Forced OR NOT aDigitalIns[nJ].bGood THEN
      aDigitalIns[nJ].bActive := bR;            // forced, or the channel just came back: no debounce
      aDigitalIns[nJ].bRawLastState := bR;
      aDigitalIns[nJ].tRawChangedAt := tNow;
    ELSE
      IF bR <> aDigitalIns[nJ].bRawLastState THEN
        aDigitalIns[nJ].bRawLastState := bR;
        aDigitalIns[nJ].tRawChangedAt := tNow;
      END_IF;
      IF tNow - aDigitalIns[nJ].tRawChangedAt >= aDigitalInSettings[nSj].tDebounceTime THEN
        aDigitalIns[nJ].bActive := aDigitalIns[nJ].bRawLastState;
      END_IF;
    END_IF;
    aDigitalIns[nJ].bGood := TRUE;
  ELSIF eWhere = E_IoQ.Unused AND bUnfittedReadsOff THEN
    aDigitalIns[nJ].bActive := FALSE;           // not fitted on this site: not active
    aDigitalIns[nJ].bGood := FALSE;
  ELSE
    aDigitalIns[nJ].bActive := aDigitalInSettings[nSj].bFailSafeState;
    aDigitalIns[nJ].bGood := FALSE;
    IF eWhere <> E_IoQ.Unused THEN
      nBad := nBad + 1;
    END_IF;
  END_IF;
  aDigitalIns[nJ].eQuality := eWhere;
  aDigitalIns[nJ].bFitted := eWhere <> E_IoQ.Unused AND eWhere <> E_IoQ.NotFitted;
  CASE eWhere OF
    E_IoQ.NoModule, E_IoQ.NoChannel: nAddr := nAddr + 1;
    E_IoQ.NotFitted: nNotFit := nNotFit + 1;
    E_IoQ.Missing: nMissFn := nMissFn + 1;
    E_IoQ.Bad: nChBad := nChBad + 1;
  ELSE
    ;
  END_CASE;
  IF nI <= 32 THEN
    IF aDigitalIns[nJ].bActive THEN nFunctionBits := nFunctionBits OR SHL(DWORD#1, nI - 1); END_IF;
    IF aDigitalIns[nJ].bGood THEN nGoodBits := nGoodBits OR SHL(DWORD#1, nI - 1); END_IF;
  END_IF;
END_FOR;

(* 5. the analog input functions *)
nAnalogGoodBits := 0;
FOR nI := 1 TO nA DO
  nSj := LOWER_BOUND(aAnalogInSettings, 1) + nI - 1;
  nJ := LOWER_BOUND(aAnalogIns, 1) + nI - 1;
  eWhere := F_IoFind(aModules := aModules, eChannelKind := E_IoKind.AnalogIn, eSource := aAnalogInSettings[nSj].eSource,
                     nModuleNumber := aAnalogInSettings[nSj].nModuleNumber, nChannel := aAnalogInSettings[nSj].nChannel, nImageFirstRow := aLo, nImageLastRow := aHi,
                     nModuleRow => nM, nImageRow => nIdx);
  IF eWhere = E_IoQ.Ok THEN
    aModules[nM].nFunctionsMapped := aModules[nM].nFunctionsMapped + 1;
    IF aAnalogInTerminals[nIdx].nFunctionRow = 0 AND nI <= 255 THEN
      aAnalogInTerminals[nIdx].nFunctionRow := DINT_TO_USINT(nI);
    END_IF;
    IF aAnalogInTerminals[nIdx].bForced THEN
      eWhere := E_IoQ.Forced;
    ELSIF NOT aModules[nM].bModuleFitted THEN
      eWhere := E_IoQ.NotFitted;
    ELSIF NOT aModules[nM].bAnswering THEN
      eWhere := E_IoQ.Missing;
    ELSIF aAnalogInTerminals[nIdx].bChannelBad THEN
      eWhere := E_IoQ.Bad;
    END_IF;
  END_IF;
  IF eWhere = E_IoQ.Ok OR eWhere = E_IoQ.Forced THEN
    aAnalogIns[nJ].fRawValue := aAnalogInTerminals[nIdx].fRawValue;
    IF eWhere = E_IoQ.Forced THEN
      FOR nK := LOWER_BOUND(aForces, 1) TO UPPER_BOUND(aForces, 1) DO
        IF aForces[nK].bForcing AND aForces[nK].eChannelKind = E_IoKind.AnalogIn AND INT_TO_DINT(aForces[nK].nImageRow) = nIdx THEN
          aAnalogIns[nJ].fRawValue := aForces[nK].fForceValue;
        END_IF;
      END_FOR;
    END_IF;
    aAnalogIns[nJ].bGood := TRUE;
  ELSIF eWhere = E_IoQ.Unused AND bUnfittedReadsOff THEN
    aAnalogIns[nJ].fRawValue := 0.0;
    aAnalogIns[nJ].bGood := FALSE;
  ELSE
    fFs := aAnalogInSettings[nSj].fFailSafeValue;
    IF NOT (ABS(fFs) <= REAL#3.4E38) THEN
      fFs := 0.0;
    END_IF;
    aAnalogIns[nJ].fRawValue := fFs;
    aAnalogIns[nJ].bGood := FALSE;
    IF eWhere <> E_IoQ.Unused THEN
      nBad := nBad + 1;
    END_IF;
  END_IF;
  aAnalogIns[nJ].eQuality := eWhere;
  aAnalogIns[nJ].bFitted := eWhere <> E_IoQ.Unused AND eWhere <> E_IoQ.NotFitted;
  CASE eWhere OF
    E_IoQ.NoModule, E_IoQ.NoChannel: nAddr := nAddr + 1;
    E_IoQ.NotFitted: nNotFit := nNotFit + 1;
    E_IoQ.Missing: nMissFn := nMissFn + 1;
    E_IoQ.Bad: nChBad := nChBad + 1;
  ELSE
    ;
  END_CASE;
  IF nI <= 32 AND aAnalogIns[nJ].bGood THEN
    nAnalogGoodBits := nAnalogGoodBits OR SHL(DWORD#1, nI - 1);
  END_IF;
END_FOR;

(* 6. the terminals for the IO page *)
nTerminalBits := 0;
nForcedBits := 0;
FOR nJ := dLo TO MIN(dHi, dLo + 31) DO
  IF aDigitalInTerminals[nJ].bTerminal THEN nTerminalBits := nTerminalBits OR SHL(DWORD#1, nJ - dLo); END_IF;
  IF aDigitalInTerminals[nJ].bForced THEN nForcedBits := nForcedBits OR SHL(DWORD#1, nJ - dLo); END_IF;
END_FOR;

(* 7. status *)
bBegun := TRUE;
bAnyForced := nForced > 0;
bMapSettingBad := bSizeBad OR nAddr > 0 OR nNotFit > 0;
bAllGood := nBad = 0 AND nMissMod = 0;
refData.sts.nForcesActive := nForced;
refData.sts.nFunctionsBad := nBad;
refData.sts.nModulesMissing := nMissMod;
refData.det.tForceTimeLeft := tLeftMax;
bError := bMapSettingBad OR NOT bSetOk;
bWarning := NOT bError AND (nForced > 0 OR nMissMod > 0 OR nMissFn > 0 OR nChBad > 0 OR refData.sts.bSettingRefused);
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
ELSIF refData.sts.bSettingRefused THEN
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
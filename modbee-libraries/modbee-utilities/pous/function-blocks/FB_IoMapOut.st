(* FB_IoMapOut — the output side of the IO map: functions to terminals, from the rows. Call it LAST in the scan,
after all logic, before your IO code copies the image to the hardware.

Pins: bForcingAllowed (outputs may be forced only while TRUE: wire the system Off; dropping it releases every
output force; unwired: never), bReleaseAllForces (release every output force now and refuse new ones), refData
(set.tForceTime; counts) and the tables (VAR_IN_OUT, sized by the project): aDigitalOutSettings / aDigitalOuts (digital output
functions: rows / live), aAnalogOutSettings / aAnalogOuts (analog), aDigitalOutTerminals / aAnalogOutTerminals (the terminals: your IO code reads bTerminal / fRawValue),
aModules (the module table, shared with FB_IoMapIn), aForces (the force slots, shared; never retained)
-> bAllGood, bAnyForced, bMapSettingBad (a wrong address, a function on a module not fitted, two functions on one
output, tables that do not match or are longer than the kept copy), the IO page's bit words nTerminalBits /
nForcedBits (the first 32 digital terminals), nFunctionBits / nGoodBits / nHeldOffBits (the first 32 digital
functions: bCommanded, bGood, bHoldOutputOff), plus FB_Object's bError / bWarning / eErrorId / eState.

The block owns the output image: every scan it first turns every output channel off (analog 0.0), then writes
each function's bCommanded / fRawValue to its channel; a force takes the place of the function's value. So a channel with no
function is off, and a function moved to another channel leaves nothing behind. One channel carries one
function: a second one on it is not written (eQuality Shared, a configuration fault). A function's bGood is TRUE when
its channel is fitted, answering and good; eQuality says what is wrong otherwise; bFitted says it is mapped on this
site. bHoldOutputOff (per digital function) holds the output off even while forced (eQuality Blocked): wire a motor's
bHoldOutputOff into it, so a commissioning force can never run a tripped motor.
Forcing: a slot names a channel (eKind DigitalOut or AnalogOut, eSource, nModuleNumber, nChannel), so spare outputs can be tested too;
only while bForcingAllowed; it ends by itself after set.tForceTime (1 ms .. 10 min, default 5 s), bCmdForceNow again
starts the time again, bCmdReleaseNow or bReleaseAllForces end it at once, every force ends at power-up.
Errors: bError for a configuration fault (IoArraySize, IoAddress, IoShared, IoNotFitted) or rows that were
never good (BadSetting); bWarning for IoForced, IoMissing, IoBad, SettingRefused.

Kept settings (a retained last-good copy, restored at power-up, a bad write put back, sts.bSettingRefused / eSettingRefusedErrorId):
each row
is its address packed into one DWORD (F_IoAddrPack: bits 0..2 eSource, 3..9 nModuleNumber 0..127, 10..17 nChannel). The
first 32 digital and 4 analog rows are kept, with set.tForceTime and the layout number: 38 retained values.
A row with an unknown source or a module over 127 is a bad write and put back.
Forces stay in the maps (see FB_IoMapIn); the slot logic is the shared F_IoForceSlot. *)

FUNCTION_BLOCK FB_IoMapOut EXTENDS FB_Object
  VAR_INPUT
    bForcingAllowed : BOOL; (* outputs may be forced only while TRUE (system Off); unwired: never *)
    bReleaseAllForces : BOOL; (* release every output force now and refuse new ones *)
    refData : REFERENCE TO ST_IoMapData; (* the map's record: force time, counts *)
  END_VAR
  VAR_IN_OUT
    aDigitalOutSettings : ARRAY [*] OF ST_IODOSET; (* digital output functions: one settings row each *)
    aDigitalOuts : ARRAY [*] OF ST_IODO; (* digital output functions: the live rows *)
    aAnalogOutSettings : ARRAY [*] OF ST_IOAOSET; (* analog output functions: one settings row each *)
    aAnalogOuts : ARRAY [*] OF ST_IOAO; (* analog output functions: the live rows *)
    aDigitalOutTerminals : ARRAY [*] OF ST_IODCH; (* the digital terminals: your IO code copies bTerminal to the hardware *)
    aAnalogOutTerminals : ARRAY [*] OF ST_IOACH; (* the analog terminals: your IO code reads fRawValue *)
    aModules : ARRAY [*] OF ST_IOMODULE; (* the module table, shared by FB_IoMapIn and FB_IoMapOut *)
    aForces : ARRAY [*] OF ST_IOFORCE; (* the force slots, shared; never retained *)
  END_VAR
  VAR_OUTPUT
    bAllGood : BOOL; (* every fitted function and fitted module is good *)
    bAnyForced : BOOL; (* a force is on *)
    bMapSettingBad : BOOL; (* a wrong address, a function on a module not fitted, or tables that do not match *)
    nTerminalBits : DWORD; (* the first 32 digital terminals, a bit each *)
    nFunctionBits : DWORD; (* the first 32 digital functions' wanted output, a bit each *)
    nGoodBits : DWORD; (* the first 32 digital functions' bGood, a bit each *)
    nForcedBits : DWORD; (* the first 32 digital terminals forced, a bit each *)
    nHeldOffBits : DWORD; (* the first 32 digital functions held off (bHoldOff), a bit each *)
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
  bAllGood := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
bSizeBad := UPPER_BOUND(aDigitalOutSettings, 1) - LOWER_BOUND(aDigitalOutSettings, 1) <> UPPER_BOUND(aDigitalOuts, 1) - LOWER_BOUND(aDigitalOuts, 1)
            OR UPPER_BOUND(aAnalogOutSettings, 1) - LOWER_BOUND(aAnalogOutSettings, 1) <> UPPER_BOUND(aAnalogOuts, 1) - LOWER_BOUND(aAnalogOuts, 1);
nD := MIN(UPPER_BOUND(aDigitalOutSettings, 1) - LOWER_BOUND(aDigitalOutSettings, 1), UPPER_BOUND(aDigitalOuts, 1) - LOWER_BOUND(aDigitalOuts, 1)) + 1;
nA := MIN(UPPER_BOUND(aAnalogOutSettings, 1) - LOWER_BOUND(aAnalogOutSettings, 1), UPPER_BOUND(aAnalogOuts, 1) - LOWER_BOUND(aAnalogOuts, 1)) + 1;
bSizeBad := bSizeBad OR nD > cDoKept OR nA > cAoKept;
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
    nSj := LOWER_BOUND(aDigitalOutSettings, 1) + nI - 1;
    IF NOT F_IoAddrOk(eSource := aDigitalOutSettings[nSj].eSource, nModuleNumber := aDigitalOutSettings[nSj].nModuleNumber) THEN
      bSetOk := FALSE;
      IF eWhy = E_UtError.None THEN eWhy := E_UtError.IoAddress; END_IF;
    END_IF;
  END_FOR;
  FOR nI := 1 TO nA DO
    nSj := LOWER_BOUND(aAnalogOutSettings, 1) + nI - 1;
    IF NOT F_IoAddrOk(eSource := aAnalogOutSettings[nSj].eSource, nModuleNumber := aAnalogOutSettings[nSj].nModuleNumber) THEN
      bSetOk := FALSE;
      IF eWhy = E_UtError.None THEN eWhy := E_UtError.IoAddress; END_IF;
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
  FOR nI := 1 TO MIN(nD, cDoKept) DO
    nSj := LOWER_BOUND(aDigitalOutSettings, 1) + nI - 1;
    bX := F_IoAddrUnpack(nPackedAddress := aKeptDo[nI], eSource => eSrc, nModuleNumber => nMod, nChannel => nCh);
    aDigitalOutSettings[nSj].eSource := eSrc;
    aDigitalOutSettings[nSj].nModuleNumber := nMod;
    aDigitalOutSettings[nSj].nChannel := nCh;
  END_FOR;
  FOR nI := 1 TO MIN(nA, cAoKept) DO
    nSj := LOWER_BOUND(aAnalogOutSettings, 1) + nI - 1;
    bX := F_IoAddrUnpack(nPackedAddress := aKeptAo[nI], eSource => eSrc, nModuleNumber => nMod, nChannel => nCh);
    aAnalogOutSettings[nSj].eSource := eSrc;
    aAnalogOutSettings[nSj].nModuleNumber := nMod;
    aAnalogOutSettings[nSj].nChannel := nCh;
  END_FOR;
  bSetOk := TRUE;                 // only good rows are ever kept
END_IF;
IF bSetOk THEN
  tKeptForceTime := refData.set.tForceTime;
  FOR nI := 1 TO MIN(nD, cDoKept) DO
    nSj := LOWER_BOUND(aDigitalOutSettings, 1) + nI - 1;
    aKeptDo[nI] := F_IoAddrPack(eSource := aDigitalOutSettings[nSj].eSource, nModuleNumber := aDigitalOutSettings[nSj].nModuleNumber, nChannel := aDigitalOutSettings[nSj].nChannel);
  END_FOR;
  FOR nI := 1 TO MIN(nA, cAoKept) DO
    nSj := LOWER_BOUND(aAnalogOutSettings, 1) + nI - 1;
    aKeptAo[nI] := F_IoAddrPack(eSource := aAnalogOutSettings[nSj].eSource, nModuleNumber := aAnalogOutSettings[nSj].nModuleNumber, nChannel := aAnalogOutSettings[nSj].nChannel);
  END_FOR;
  nKeptLayout := cLayout;
END_IF;
tFt := refData.set.tForceTime;
IF tFt <= T#0s THEN
  tFt := T#5s;
ELSIF tFt > T#10m THEN
  tFt := T#10m;
END_IF;
dLo := LOWER_BOUND(aDigitalOutTerminals, 1);
dHi := UPPER_BOUND(aDigitalOutTerminals, 1);
aLo := LOWER_BOUND(aAnalogOutTerminals, 1);
aHi := UPPER_BOUND(aAnalogOutTerminals, 1);

(* 1. every output channel off; nothing forced, no function yet *)
FOR nJ := dLo TO dHi DO
  aDigitalOutTerminals[nJ].bTerminal := FALSE;
  aDigitalOutTerminals[nJ].bForced := FALSE;
  aDigitalOutTerminals[nJ].nFunctionRow := 0;
END_FOR;
FOR nJ := aLo TO aHi DO
  aAnalogOutTerminals[nJ].fRawValue := 0.0;
  aAnalogOutTerminals[nJ].bForced := FALSE;
  aAnalogOutTerminals[nJ].nFunctionRow := 0;
END_FOR;

(* 2. the output modules *)
nMissMod := 0;
FOR nK := LOWER_BOUND(aModules, 1) TO UPPER_BOUND(aModules, 1) DO
  IF aModules[nK].eChannelKind = E_IoKind.DigitalOut OR aModules[nK].eChannelKind = E_IoKind.AnalogOut THEN
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

(* 3. the force slots for outputs: the forced value goes on the terminal *)
nForced := 0;
tLeftMax := T#0s;
FOR nJ := LOWER_BOUND(aForces, 1) TO UPPER_BOUND(aForces, 1) DO
  eKind := aForces[nJ].eChannelKind;
  IF eKind = E_IoKind.DigitalOut OR eKind = E_IoKind.AnalogOut THEN
    IF eKind = E_IoKind.DigitalOut THEN
      eWhere := F_IoFind(aModules := aModules, eChannelKind := eKind, eSource := aForces[nJ].eSource, nModuleNumber := aForces[nJ].nModuleNumber,
                         nChannel := aForces[nJ].nChannel, nImageFirstRow := dLo, nImageLastRow := dHi, nModuleRow => nM, nImageRow => nIdx);
    ELSE
      eWhere := F_IoFind(aModules := aModules, eChannelKind := eKind, eSource := aForces[nJ].eSource, nModuleNumber := aForces[nJ].nModuleNumber,
                         nChannel := aForces[nJ].nChannel, nImageFirstRow := aLo, nImageLastRow := aHi, nModuleRow => nM, nImageRow => nIdx);
    END_IF;
    IF eWhere = E_IoQ.Unused THEN
      eWhere := E_IoQ.NoModule;
    END_IF;
    IF F_IoForceSlot(stForceSlot := aForces[nJ], eAddressQuality := eWhere, bForcingAllowed := bForcingAllowed,
                     bReleaseAllForces := bReleaseAllForces OR NOT bBegun, tNow := tNow, tForceTime := tFt) THEN
      aForces[nJ].nImageRow := DINT_TO_INT(nIdx);
      IF eKind = E_IoKind.DigitalOut THEN
        aDigitalOutTerminals[nIdx].bTerminal := aForces[nJ].bForceState;
        aDigitalOutTerminals[nIdx].bForced := TRUE;
      ELSE
        aAnalogOutTerminals[nIdx].fRawValue := aForces[nJ].fForceValue;
        aAnalogOutTerminals[nIdx].bForced := TRUE;
      END_IF;
      nForced := nForced + 1;
      IF aForces[nJ].tTimeLeft > tLeftMax THEN
        tLeftMax := aForces[nJ].tTimeLeft;
      END_IF;
    END_IF;
  END_IF;
END_FOR;

(* 4. the digital functions: bCommanded to the channel unless forced; bHoldOutputOff beats both *)
nBad := 0;
nAddr := 0;
nShared := 0;
nNotFit := 0;
nMissFn := 0;
nChBad := 0;
nFunctionBits := 0;
nGoodBits := 0;
nHeldOffBits := 0;
FOR nI := 1 TO nD DO
  nSj := LOWER_BOUND(aDigitalOutSettings, 1) + nI - 1;
  nJ := LOWER_BOUND(aDigitalOuts, 1) + nI - 1;
  aDigitalOuts[nJ].bOutput := FALSE;
  eWhere := F_IoFind(aModules := aModules, eChannelKind := E_IoKind.DigitalOut, eSource := aDigitalOutSettings[nSj].eSource,
                     nModuleNumber := aDigitalOutSettings[nSj].nModuleNumber, nChannel := aDigitalOutSettings[nSj].nChannel, nImageFirstRow := dLo, nImageLastRow := dHi,
                     nModuleRow => nM, nImageRow => nIdx);
  IF eWhere = E_IoQ.Ok THEN
    IF aDigitalOutTerminals[nIdx].nFunctionRow <> 0 THEN
      eWhere := E_IoQ.Shared;
    ELSE
      aModules[nM].nFunctionsMapped := aModules[nM].nFunctionsMapped + 1;
      aDigitalOutTerminals[nIdx].nFunctionRow := DINT_TO_USINT(MIN(nI, 255));
      IF NOT aModules[nM].bModuleFitted THEN
        eWhere := E_IoQ.NotFitted;
      ELSIF NOT aModules[nM].bAnswering THEN
        eWhere := E_IoQ.Missing;
      ELSIF aDigitalOutTerminals[nIdx].bChannelBad THEN
        eWhere := E_IoQ.Bad;
      END_IF;
      IF NOT aDigitalOutTerminals[nIdx].bForced THEN
        aDigitalOutTerminals[nIdx].bTerminal := aDigitalOuts[nJ].bCommanded;
      END_IF;
      IF aDigitalOuts[nJ].bHoldOutputOff THEN
        aDigitalOutTerminals[nIdx].bTerminal := FALSE;
      END_IF;
      aDigitalOuts[nJ].bOutput := aDigitalOutTerminals[nIdx].bTerminal;
    END_IF;
  END_IF;
  aDigitalOuts[nJ].bGood := eWhere = E_IoQ.Ok;
  aDigitalOuts[nJ].bFitted := eWhere <> E_IoQ.Unused AND eWhere <> E_IoQ.NotFitted;
  IF NOT aDigitalOuts[nJ].bGood AND eWhere <> E_IoQ.Unused THEN
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
    IF aDigitalOutTerminals[nIdx].bForced THEN    // (nested: IEC AND does not short-circuit, idx is valid only here)
      IF aDigitalOuts[nJ].bHoldOutputOff THEN
        eWhere := E_IoQ.Blocked;
      ELSE
        eWhere := E_IoQ.Forced;
      END_IF;
    END_IF;
  END_IF;
  aDigitalOuts[nJ].eQuality := eWhere;
  IF nI <= 32 THEN
    IF aDigitalOuts[nJ].bCommanded THEN nFunctionBits := nFunctionBits OR SHL(DWORD#1, nI - 1); END_IF;
    IF aDigitalOuts[nJ].bGood THEN nGoodBits := nGoodBits OR SHL(DWORD#1, nI - 1); END_IF;
    IF aDigitalOuts[nJ].bHoldOutputOff THEN nHeldOffBits := nHeldOffBits OR SHL(DWORD#1, nI - 1); END_IF;
  END_IF;
END_FOR;

(* 5. the analog functions *)
FOR nI := 1 TO nA DO
  nSj := LOWER_BOUND(aAnalogOutSettings, 1) + nI - 1;
  nJ := LOWER_BOUND(aAnalogOuts, 1) + nI - 1;
  aAnalogOuts[nJ].fOutput := 0.0;
  eWhere := F_IoFind(aModules := aModules, eChannelKind := E_IoKind.AnalogOut, eSource := aAnalogOutSettings[nSj].eSource,
                     nModuleNumber := aAnalogOutSettings[nSj].nModuleNumber, nChannel := aAnalogOutSettings[nSj].nChannel, nImageFirstRow := aLo, nImageLastRow := aHi,
                     nModuleRow => nM, nImageRow => nIdx);
  IF eWhere = E_IoQ.Ok THEN
    IF aAnalogOutTerminals[nIdx].nFunctionRow <> 0 THEN
      eWhere := E_IoQ.Shared;
    ELSE
      aModules[nM].nFunctionsMapped := aModules[nM].nFunctionsMapped + 1;
      aAnalogOutTerminals[nIdx].nFunctionRow := DINT_TO_USINT(MIN(nI, 255));
      IF NOT aModules[nM].bModuleFitted THEN
        eWhere := E_IoQ.NotFitted;
      ELSIF NOT aModules[nM].bAnswering THEN
        eWhere := E_IoQ.Missing;
      ELSIF aAnalogOutTerminals[nIdx].bChannelBad THEN
        eWhere := E_IoQ.Bad;
      END_IF;
      IF NOT aAnalogOutTerminals[nIdx].bForced THEN
        aAnalogOutTerminals[nIdx].fRawValue := aAnalogOuts[nJ].fRawValue;
      END_IF;
      aAnalogOuts[nJ].fOutput := aAnalogOutTerminals[nIdx].fRawValue;
    END_IF;
  END_IF;
  aAnalogOuts[nJ].bGood := eWhere = E_IoQ.Ok;
  aAnalogOuts[nJ].bFitted := eWhere <> E_IoQ.Unused AND eWhere <> E_IoQ.NotFitted;
  IF NOT aAnalogOuts[nJ].bGood AND eWhere <> E_IoQ.Unused THEN
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
    IF aAnalogOutTerminals[nIdx].bForced THEN
      eWhere := E_IoQ.Forced;
    END_IF;
  END_IF;
  aAnalogOuts[nJ].eQuality := eWhere;
END_FOR;

(* 6. the terminals for the IO page *)
nTerminalBits := 0;
nForcedBits := 0;
FOR nJ := dLo TO MIN(dHi, dLo + 31) DO
  IF aDigitalOutTerminals[nJ].bTerminal THEN nTerminalBits := nTerminalBits OR SHL(DWORD#1, nJ - dLo); END_IF;
  IF aDigitalOutTerminals[nJ].bForced THEN nForcedBits := nForcedBits OR SHL(DWORD#1, nJ - dLo); END_IF;
END_FOR;

(* 7. status *)
bBegun := TRUE;
bAnyForced := nForced > 0;
bMapSettingBad := bSizeBad OR nAddr > 0 OR nShared > 0 OR nNotFit > 0;
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
(* FB_PulseSeq — sequential pulsing: jet-pulse filter cleaning, flush valves, staged outputs.
aOutputs (the project's row of valves, one element per channel) is pulsed one at a time in order: each channel
gets set.nPulsesPerChannel pulses of tPulseOnTime with tGapBetweenPulses between them, then tGapBetweenChannels before the next channel.
After the last channel the cycle is done (bCycleDone for one scan) and, while cleaning is still wanted, tPauseAfterCycle
passes before the next cycle. Never more than one output is on.
Cleaning is wanted while bEnable AND bCleaningDemand (bCleaningDemand defaults TRUE, so bEnable alone runs it continuously), after
tStartDelay. When that ends: nPostCleanCycles = 0 stops at once (an output that is on goes off); nPostCleanCycles > 0
finishes the cycle and runs that many more full cycles (post-clean, also after the fan stops). bCleanCycleNow / bCmdCleanCycleNow
runs one full cycle now (a manual clean); bStop / bCmdStop stops at once, and demand cleaning waits until bCleaningDemand
or bEnable has dropped and come back. bPause pauses where it is: the output goes off, the interrupted pulse is given
again in full on release; gaps and pauses keep their remaining time.
Channels count from 1 = the first element, whatever the array's lower bound; set.nSkipChannelBits bit n skips channel n+1
(channels above 32 cannot be skipped). Every channel skipped (or no outputs): bError NoChannels, nothing runs.
Nothing is kept over a power cut but the settings (a retained last-good copy, a bad write put back); sts.nCycleCount
counts from power-up. A command the HMI keeps writing TRUE acts once. *)

FUNCTION_BLOCK FB_PulseSeq EXTENDS FB_Object
  VAR_INPUT
    bEnable : BOOL; (* allow operation (e.g. the fan running) *)
    bCleaningDemand : BOOL := TRUE; (* on-demand cleaning (e.g. DP high); TRUE for continuous *)
    bPause : BOOL; (* pause where it is *)
    bCleanCycleNow : BOOL R_EDGE; (* one full cleaning cycle now *)
    bStop : BOOL R_EDGE; (* stop now *)
    refData : REFERENCE TO ST_PulseSeqData; (* the block's record *)
  END_VAR
  VAR_IN_OUT
    aOutputs : ARRAY [*] OF BOOL; (* the project's row of valves, one element per channel *)
  END_VAR
  VAR_OUTPUT
    bBusy : BOOL; (* cleaning is running *)
    nChannelNow : INT; (* the channel pulsing (0 = none) *)
    bCycleDone : BOOL; (* one scan at the end of each full cycle *)
  END_VAR
  VAR RETAIN
    stKept : ST_PulseSeqSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    tPrev : TIME;
    nCh : DINT; (* the channel (position) being worked on *)
    ePh : E_PulsePhase;
    tAcc : TIME; (* time in the phase (held time not counted) *)
    nPulseNo : INT;
    nPostLeft : INT;
    bManual : BOOL;
    bInhibit : BOOL;
    bDemandPrev : BOOL;
    bStartSeen : BOOL;
    bStopSeen : BOOL;
    bHeldPrev : BOOL;
    nCycles : UDINT;
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    tScan : TIME;
    nLo : DINT;
    nHi : DINT;
    nN : DINT;
    nI : DINT;
    nP : DINT;
    nNx : DINT;
    nPpc : INT;
    bDemandNow : BOOL;
    bStartReq : BOOL;
    bStopReq : BOOL;
    bBeginCycle : BOOL;
    bAnyCh : BOOL;
  END_VAR


(* the settings are usable *)
METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_PulseSeqSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.nPulsesPerChannel >= 1) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.nPostCleanCycles >= 0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.tPulseOnTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tGapBetweenPulses >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tGapBetweenChannels >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tPauseAfterCycle >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tStartDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_PulseSeqSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

(* channel nP (1-based) is not skipped *)
METHOD PRIVATE Usable : BOOL
  VAR_INPUT
    nP : DINT;
  END_VAR
  IF nP > 32 THEN
    Usable := TRUE;
  ELSE
    Usable := (SHR(refData.set.nSkipChannelBits, DINT_TO_INT(nP - 1)) AND DWORD#16#1) = DWORD#0;
  END_IF;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
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
  tPrev := tNow;
END_IF;
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
  bOk := TRUE;
END_IF;
IF SystemReset() THEN
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;
nLo := LOWER_BOUND(aOutputs, 1);
nHi := UPPER_BOUND(aOutputs, 1);
nN := nHi - nLo + 1;
bCycleDone := FALSE;
tScan := tNow - tPrev;
tPrev := tNow;
IF tScan < T#0s THEN
  tScan := T#0s;
END_IF;
nPpc := MAX(1, refData.set.nPulsesPerChannel);

(* HMI commands: once per write, then cleared *)
bStartReq := bCleanCycleNow OR (refData.bCmdCleanCycleNow AND NOT bStartSeen);
bStartSeen := refData.bCmdCleanCycleNow;
refData.bCmdCleanCycleNow := FALSE;
bStopReq := bStop OR (refData.bCmdStop AND NOT bStopSeen);
bStopSeen := refData.bCmdStop;
refData.bCmdStop := FALSE;
IF bStopReq THEN
  ePh := E_PulsePhase.Idle;
  bManual := FALSE;
  nPostLeft := 0;
  bInhibit := TRUE;               (* demand cleaning waits for bCleaningDemand / bEnable to come back *)
ELSIF bStartReq THEN
  bManual := TRUE;
  bInhibit := FALSE;
END_IF;
IF NOT (bEnable AND bCleaningDemand) THEN
  bInhibit := FALSE;
END_IF;
bDemandNow := bEnable AND bCleaningDemand AND NOT bInhibit;
IF bStopReq THEN
  bDemandPrev := bDemandNow;
END_IF;

(* demand ends during a run: stop now, or finish with post-clean cycles *)
IF ePh >= E_PulsePhase.PulseOn THEN
  IF bDemandPrev AND NOT bDemandNow THEN
    IF refData.set.nPostCleanCycles > 0 THEN
      nPostLeft := refData.set.nPostCleanCycles;
    ELSIF NOT bManual THEN
      ePh := E_PulsePhase.Idle;
    END_IF;
  ELSIF bDemandNow AND NOT bDemandPrev THEN
    nPostLeft := 0;
  END_IF;
END_IF;
bDemandPrev := bDemandNow;

bBeginCycle := FALSE;
CASE ePh OF
E_PulsePhase.Idle:
  IF bManual THEN
    bBeginCycle := TRUE;
  ELSIF bDemandNow THEN
    ePh := E_PulsePhase.StartDelay;
    tAcc := T#0s;
    IF refData.set.tStartDelay <= T#0s AND NOT bPause THEN
      bBeginCycle := TRUE;
    END_IF;
  END_IF;
E_PulsePhase.StartDelay:
  IF bManual THEN
    bBeginCycle := TRUE;
  ELSIF NOT bDemandNow THEN
    ePh := E_PulsePhase.Idle;
  ELSIF NOT bPause THEN
    tAcc := tAcc + tScan;
    IF tAcc >= refData.set.tStartDelay THEN
      bBeginCycle := TRUE;
    END_IF;
  END_IF;
ELSE
  IF bPause THEN
    IF ePh = E_PulsePhase.PulseOn THEN
      tAcc := T#0s;               (* the interrupted pulse is given again in full *)
    END_IF;
  ELSIF bHeldPrev AND ePh = E_PulsePhase.PulseOn THEN
    tAcc := T#0s;                 (* released: the pulse starts now, on for at least this scan *)
  ELSE
    tAcc := tAcc + tScan;
    CASE ePh OF
    E_PulsePhase.PulseOn:
      IF tAcc >= refData.set.tPulseOnTime THEN
        tAcc := T#0s;
        IF nPulseNo < nPpc THEN
          ePh := E_PulsePhase.PulseGap;
        ELSE
          nNx := 0;               (* the next channel not skipped *)
          FOR nP := nN TO nCh + 1 BY -1 DO
            IF Usable(nP := nP) THEN
              nNx := nP;
            END_IF;
          END_FOR;
          IF nNx > 0 THEN
            nCh := nNx;
            ePh := E_PulsePhase.ChannelGap;
          ELSE
            bCycleDone := TRUE;   (* the end of the cycle *)
            nCycles := nCycles + 1;
            bManual := FALSE;
            IF bDemandNow OR nPostLeft > 0 THEN
              ePh := E_PulsePhase.CyclePause;
            ELSE
              ePh := E_PulsePhase.Idle;
            END_IF;
          END_IF;
        END_IF;
      END_IF;
    E_PulsePhase.PulseGap:
      IF tAcc >= refData.set.tGapBetweenPulses THEN
        tAcc := T#0s;
        nPulseNo := nPulseNo + 1;
        ePh := E_PulsePhase.PulseOn;
      END_IF;
    E_PulsePhase.ChannelGap:
      IF tAcc >= refData.set.tGapBetweenChannels THEN
        tAcc := T#0s;
        nPulseNo := 1;
        ePh := E_PulsePhase.PulseOn;
      END_IF;
    E_PulsePhase.CyclePause:
      IF tAcc >= refData.set.tPauseAfterCycle THEN
        IF bDemandNow OR bManual OR nPostLeft > 0 THEN
          bBeginCycle := TRUE;
        ELSE
          ePh := E_PulsePhase.Idle;
        END_IF;
      END_IF;
    END_CASE;
  END_IF;
END_CASE;
bHeldPrev := bPause;
IF bBeginCycle THEN
  nNx := 0;                       (* the first channel not skipped; none = nothing to do *)
  FOR nP := nN TO 1 BY -1 DO
    IF Usable(nP := nP) THEN
      nNx := nP;
    END_IF;
  END_FOR;
  IF nNx > 0 THEN
    IF NOT bDemandNow AND NOT bManual AND nPostLeft > 0 THEN
      nPostLeft := nPostLeft - 1; (* a post-clean cycle *)
    END_IF;
    nCh := nNx;
    nPulseNo := 1;
    ePh := E_PulsePhase.PulseOn;
    tAcc := T#0s;
  ELSE
    ePh := E_PulsePhase.Idle;
    bManual := FALSE;
    nPostLeft := 0;
  END_IF;
END_IF;
IF ePh = E_PulsePhase.Idle THEN
  nPostLeft := 0;
  bManual := FALSE;
END_IF;

(* one output at most *)
FOR nI := nLo TO nHi DO
  aOutputs[nI] := ePh = E_PulsePhase.PulseOn AND NOT bPause AND nI - nLo + 1 = nCh;
END_FOR;
bBusy := ePh >= E_PulsePhase.PulseOn;
IF ePh = E_PulsePhase.PulseOn OR ePh = E_PulsePhase.PulseGap THEN
  nChannelNow := DINT_TO_INT(nCh);
  refData.sts.nPulseOnChannel := nPulseNo;
ELSE
  nChannelNow := 0;
  refData.sts.nPulseOnChannel := 0;
END_IF;
IF ePh = E_PulsePhase.ChannelGap THEN
  refData.sts.nChannelNow := DINT_TO_INT(nCh);   (* the channel gap: the channel next *)
ELSE
  refData.sts.nChannelNow := nChannelNow;
END_IF;
CASE ePh OF
  E_PulsePhase.StartDelay: refData.sts.tTimeLeft := refData.set.tStartDelay - tAcc;
  E_PulsePhase.PulseOn: refData.sts.tTimeLeft := refData.set.tPulseOnTime - tAcc;
  E_PulsePhase.PulseGap: refData.sts.tTimeLeft := refData.set.tGapBetweenPulses - tAcc;
  E_PulsePhase.ChannelGap: refData.sts.tTimeLeft := refData.set.tGapBetweenChannels - tAcc;
  E_PulsePhase.CyclePause: refData.sts.tTimeLeft := refData.set.tPauseAfterCycle - tAcc;
ELSE
  refData.sts.tTimeLeft := T#0s;
END_CASE;
IF refData.sts.tTimeLeft < T#0s THEN
  refData.sts.tTimeLeft := T#0s;
END_IF;
refData.sts.ePulsePhase := ePh;
refData.sts.nCycleCount := nCycles;
refData.sts.nPostCleanCyclesLeft := nPostLeft;
refData.sts.bWaitDemandDrop := bInhibit;

(* errors *)
bAnyCh := FALSE;
FOR nP := 1 TO nN DO
  IF Usable(nP := nP) THEN
    bAnyCh := TRUE;
    EXIT;
  END_IF;
END_FOR;
bError := NOT bAnyCh OR NOT bOk;
bWarning := NOT bError AND refData.sts.bSettingRefused;
IF NOT bAnyCh THEN
  eErrorId := E_UtError.NoChannels;
ELSIF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF bPause AND ePh <> E_PulsePhase.Idle THEN
  eState := E_State.Held;
ELSIF ePh = E_PulsePhase.StartDelay OR bInhibit OR ePh = E_PulsePhase.CyclePause THEN
  eState := E_State.Waiting;
ELSIF bBusy THEN
  eState := E_State.Running;
ELSIF NOT bEnable THEN
  eState := E_State.Off;
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK
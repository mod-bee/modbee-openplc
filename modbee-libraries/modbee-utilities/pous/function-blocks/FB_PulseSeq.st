(* FB_PulseSeq — sequential pulsing: jet-pulse filter cleaning, flush valves, staged outputs (src-v2 UT_PULSE_SEQ, the
same rules under 0.2 names).
aOutputs (the project's row of valves, one element per channel) is pulsed one at a time in order: each channel
gets set.nPulsesPerChannel pulses of tPulseOn with tPulseOff between them, then tChannelGap before the next channel.
After the last channel the cycle is done (bCycleDone for one scan) and, while cleaning is still wanted, tCyclePause
passes before the next cycle. Never more than one output is on.
Cleaning is wanted while bEnable AND bDemand (bDemand defaults TRUE, so bEnable alone runs it continuously), after
tStartDelay. When that ends: nPostCycles = 0 stops at once (an output that is on goes off); nPostCycles > 0
finishes the cycle and runs that many more full cycles (post-clean, also after the fan stops). bStart / bCmdStart
runs one full cycle now (a manual clean); bStop / bCmdStop stops at once, and demand cleaning waits until bDemand
or bEnable has dropped and come back. bHold pauses where it is: the output goes off, the interrupted pulse is given
again in full on release; gaps and pauses keep their remaining time.
Channels count from 1 = the first element, whatever the array's lower bound; set.nSkip bit n skips channel n+1
(channels above 32 cannot be skipped). Every channel skipped (or no outputs): bError NoChannels, nothing runs.
Nothing is kept over a power cut but the settings (a retained last-good copy, a bad write put back); sts.nCycles
counts from power-up. A command the HMI keeps writing TRUE acts once. *)

FUNCTION_BLOCK FB_PulseSeq EXTENDS FB_Object
  VAR_INPUT
    bEnable : BOOL; (* allow operation (e.g. the fan running) *)
    bDemand : BOOL := TRUE; (* on-demand cleaning (e.g. DP high); TRUE for continuous *)
    bHold : BOOL; (* pause where it is *)
    bStart : BOOL R_EDGE; (* one full cleaning cycle now *)
    bStop : BOOL R_EDGE; (* stop now *)
    refData : REFERENCE TO ST_PulseSeqData;
  END_VAR
  VAR_IN_OUT
    aOutputs : ARRAY [*] OF BOOL;
  END_VAR
  VAR_OUTPUT
    bBusy : BOOL;
    nChannel : INT; (* the channel pulsing (0 = none) *)
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
METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_PulseSeqSet;
  END_VAR
  SetOk := stS.nPulsesPerChannel >= 1 AND stS.nPostCycles >= 0 AND stS.tPulseOn >= T#0s AND stS.tPulseOff >= T#0s
           AND stS.tChannelGap >= T#0s AND stS.tCyclePause >= T#0s AND stS.tStartDelay >= T#0s;
END_METHOD

(* channel nP (1-based) is not skipped *)
METHOD PRIVATE Usable : BOOL
  VAR_INPUT
    nP : DINT;
  END_VAR
  IF nP > 32 THEN
    Usable := TRUE;
  ELSE
    Usable := (SHR(refData.set.nSkip, DINT_TO_INT(nP - 1)) AND DWORD#16#1) = DWORD#0;
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
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOk := TRUE;
END_IF;
IF SystemReset() THEN
  refData.sts.bRefused := FALSE;
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
bStartReq := bStart OR (refData.bCmdStart AND NOT bStartSeen);
bStartSeen := refData.bCmdStart;
refData.bCmdStart := FALSE;
bStopReq := bStop OR (refData.bCmdStop AND NOT bStopSeen);
bStopSeen := refData.bCmdStop;
refData.bCmdStop := FALSE;
IF bStopReq THEN
  ePh := E_PulsePhase.Idle;
  bManual := FALSE;
  nPostLeft := 0;
  bInhibit := TRUE;               (* demand cleaning waits for bDemand / bEnable to come back *)
ELSIF bStartReq THEN
  bManual := TRUE;
  bInhibit := FALSE;
END_IF;
IF NOT (bEnable AND bDemand) THEN
  bInhibit := FALSE;
END_IF;
bDemandNow := bEnable AND bDemand AND NOT bInhibit;
IF bStopReq THEN
  bDemandPrev := bDemandNow;
END_IF;

(* demand ends during a run: stop now, or finish with post-clean cycles *)
IF ePh >= E_PulsePhase.PulseOn THEN
  IF bDemandPrev AND NOT bDemandNow THEN
    IF refData.set.nPostCycles > 0 THEN
      nPostLeft := refData.set.nPostCycles;
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
    IF refData.set.tStartDelay <= T#0s AND NOT bHold THEN
      bBeginCycle := TRUE;
    END_IF;
  END_IF;
E_PulsePhase.StartDelay:
  IF bManual THEN
    bBeginCycle := TRUE;
  ELSIF NOT bDemandNow THEN
    ePh := E_PulsePhase.Idle;
  ELSIF NOT bHold THEN
    tAcc := tAcc + tScan;
    IF tAcc >= refData.set.tStartDelay THEN
      bBeginCycle := TRUE;
    END_IF;
  END_IF;
ELSE
  IF bHold THEN
    IF ePh = E_PulsePhase.PulseOn THEN
      tAcc := T#0s;               (* the interrupted pulse is given again in full *)
    END_IF;
  ELSIF bHeldPrev AND ePh = E_PulsePhase.PulseOn THEN
    tAcc := T#0s;                 (* released: the pulse starts now, on for at least this scan *)
  ELSE
    tAcc := tAcc + tScan;
    CASE ePh OF
    E_PulsePhase.PulseOn:
      IF tAcc >= refData.set.tPulseOn THEN
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
      IF tAcc >= refData.set.tPulseOff THEN
        tAcc := T#0s;
        nPulseNo := nPulseNo + 1;
        ePh := E_PulsePhase.PulseOn;
      END_IF;
    E_PulsePhase.ChannelGap:
      IF tAcc >= refData.set.tChannelGap THEN
        tAcc := T#0s;
        nPulseNo := 1;
        ePh := E_PulsePhase.PulseOn;
      END_IF;
    E_PulsePhase.CyclePause:
      IF tAcc >= refData.set.tCyclePause THEN
        IF bDemandNow OR bManual OR nPostLeft > 0 THEN
          bBeginCycle := TRUE;
        ELSE
          ePh := E_PulsePhase.Idle;
        END_IF;
      END_IF;
    END_CASE;
  END_IF;
END_CASE;
bHeldPrev := bHold;
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
  aOutputs[nI] := ePh = E_PulsePhase.PulseOn AND NOT bHold AND nI - nLo + 1 = nCh;
END_FOR;
bBusy := ePh >= E_PulsePhase.PulseOn;
IF ePh = E_PulsePhase.PulseOn OR ePh = E_PulsePhase.PulseGap THEN
  nChannel := DINT_TO_INT(nCh);
  refData.sts.nPulse := nPulseNo;
ELSE
  nChannel := 0;
  refData.sts.nPulse := 0;
END_IF;
IF ePh = E_PulsePhase.ChannelGap THEN
  refData.sts.nChannel := DINT_TO_INT(nCh);   (* the channel gap: the channel next *)
ELSE
  refData.sts.nChannel := nChannel;
END_IF;
CASE ePh OF
  E_PulsePhase.StartDelay: refData.sts.tTimeLeft := refData.set.tStartDelay - tAcc;
  E_PulsePhase.PulseOn: refData.sts.tTimeLeft := refData.set.tPulseOn - tAcc;
  E_PulsePhase.PulseGap: refData.sts.tTimeLeft := refData.set.tPulseOff - tAcc;
  E_PulsePhase.ChannelGap: refData.sts.tTimeLeft := refData.set.tChannelGap - tAcc;
  E_PulsePhase.CyclePause: refData.sts.tTimeLeft := refData.set.tCyclePause - tAcc;
ELSE
  refData.sts.tTimeLeft := T#0s;
END_CASE;
IF refData.sts.tTimeLeft < T#0s THEN
  refData.sts.tTimeLeft := T#0s;
END_IF;
refData.sts.ePhase := ePh;
refData.sts.nCycles := nCycles;
refData.sts.nPostLeft := nPostLeft;
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
bWarning := NOT bError AND refData.sts.bRefused;
IF NOT bAnyCh THEN
  eErrorId := E_UtError.NoChannels;
ELSIF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF bHold AND ePh <> E_PulsePhase.Idle THEN
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
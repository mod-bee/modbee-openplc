(* UT_PULSE_SEQ — sequential pulsing (jet-pulse filter cleaning, flush valves,
staged outputs).

Outputs is the row of valves, one element per channel, pulsed one at a
time in order: each channel gets `pulsesPerChannel` pulses of `pulseOn`
with `pulseOff` between them, then `channelGap` before the next channel.
After the last channel the cycle is done (CycleDone for one scan) and,
while cleaning is still wanted, `cyclePause` passes before the next cycle.
Never more than one output is on.

Cleaning is wanted while Enable AND Demand (Demand defaults TRUE, so
Enable alone runs it continuously), after `startDelay`. When that ends:
postCycles = 0 stops at once (an output that is on goes off); postCycles > 0
finishes the cycle and runs that many more full cycles (post-clean, also
after the fan stops). Start / cmdStart runs one full cycle now (manual clean);
Stop / cmdStop stops at once, and demand cleaning waits until Demand or Enable has
dropped and come back.

Hold pauses where it is: the output goes off, and the interrupted pulse is
given again in full on release; gaps and pauses keep their remaining time.

Channels are counted from 1 = the first element, whatever the array's
lower bound. `skip` bit n skips channel n+1 (channels above 32 cannot be
skipped). With every channel skipped nothing runs. Nothing is kept over a
power cut except the settings (kept; a bad write is put back): `cycles`
counts from when the PLC started. *)

FUNCTION_BLOCK UT_PULSE_SEQ
  VAR_INPUT
    Enable : BOOL; (* allow operation (e.g. fan running) *)
    Demand : BOOL := TRUE; (* on-demand cleaning (e.g. DP high); leave TRUE for continuous *)
    Hold : BOOL; (* pause where it is *)
    Start : BOOL R_EDGE; (* one full cleaning cycle now *)
    Stop : BOOL R_EDGE; (* stop now *)
  END_VAR
  VAR_OUTPUT
    Busy : BOOL;
    Channel : INT; (* channel pulsing (0 = none) *)
    CycleDone : BOOL; (* one scan at the end of each full cycle *)
    Fault : BOOL; (* no channel to pulse *)
    Warning : BOOL; (* a bad setting at first boot (a safe value is used) *)
  END_VAR
  VAR_IN_OUT
    Outputs : ARRAY [*] OF BOOL;
    Data : UT_PULSE_SEQ_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_PULSE_SEQ_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    ok : BOOL;
    started : BOOL;
    tCur : TIME;
    tPrev : TIME;
    dtScan : TIME;
    lo : DINT;
    hi : DINT;
    n : DINT;
    i : DINT;
    p : DINT;
    ch : DINT; (* channel (position) being worked on *)
    nx : DINT;
    ph : INT; (* 0 idle, 1 start delay, 2 pulse on, 3 pulse gap, 4 channel gap, 5 cycle pause *)
    acc : TIME; (* time in the phase (held time not counted) *)
    pulseNo : INT;
    ppc : INT;
    postLeft : INT;
    manual : BOOL;
    inhibit : BOOL;
    demandNow : BOOL;
    demandPrev : BOOL;
    startSeen : BOOL;
    stopSeen : BOOL;
    startReq : BOOL;
    stopReq : BOOL;
    beginCycle : BOOL;
    heldPrev : BOOL;
    cycles : UDINT;
    anyCh : BOOL; (* a channel that is not skipped *)
    sc : UT_STATUS; (* status code *)
    sf : UT_FAULT; (* and what it is about *)
    shownSt : UT_STATUS; (* the status the text was set for *)
    shownF : UT_FAULT;
    shown : BOOL;
  END_VAR


tCur := TIME();
keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := UT_PULSE_SEQ_CHECK(S := Data.set);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_SETTING;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := TRUE;
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;
lo := LOWER_BOUND(Outputs, 1);
hi := UPPER_BOUND(Outputs, 1);
n := hi - lo + 1;
CycleDone := FALSE;
IF NOT started THEN
  started := TRUE;
  tPrev := tCur;
END_IF;
dtScan := tCur - tPrev;
tPrev := tCur;
IF dtScan < T#0s THEN
  dtScan := T#0s;
END_IF;
IF Data.set.pulsesPerChannel < 1 THEN
  ppc := 1;
ELSE
  ppc := Data.set.pulsesPerChannel;
END_IF;

(* HMI commands: once per request, then cleared *)
startReq := Start OR (Data.cmdStart AND NOT startSeen);
startSeen := Data.cmdStart;
Data.cmdStart := FALSE;
stopReq := Stop OR (Data.cmdStop AND NOT stopSeen);
stopSeen := Data.cmdStop;
Data.cmdStop := FALSE;

IF stopReq THEN
  ph := 0;
  manual := FALSE;
  postLeft := 0;
  inhibit := TRUE;               (* demand cleaning waits for Demand / Enable to come back *)
ELSIF startReq THEN
  manual := TRUE;
  inhibit := FALSE;
END_IF;
IF NOT (Enable AND Demand) THEN
  inhibit := FALSE;
END_IF;
demandNow := Enable AND Demand AND NOT inhibit;
IF stopReq THEN
  demandPrev := demandNow;
END_IF;

(* demand ends during a run: stop now, or finish with post-clean cycles *)
IF ph >= 2 THEN
  IF demandPrev AND NOT demandNow THEN
    IF Data.set.postCycles > 0 THEN
      postLeft := Data.set.postCycles;
    ELSIF NOT manual THEN
      ph := 0;
    END_IF;
  ELSIF demandNow AND NOT demandPrev THEN
    postLeft := 0;
  END_IF;
END_IF;
demandPrev := demandNow;

beginCycle := FALSE;
CASE ph OF
0:
  IF manual THEN
    beginCycle := TRUE;
  ELSIF demandNow THEN
    ph := 1;
    acc := T#0s;
    IF Data.set.startDelay <= T#0s AND NOT Hold THEN
      beginCycle := TRUE;
    END_IF;
  END_IF;
1:
  IF manual THEN
    beginCycle := TRUE;
  ELSIF NOT demandNow THEN
    ph := 0;
  ELSIF NOT Hold THEN
    acc := acc + dtScan;
    IF acc >= Data.set.startDelay THEN
      beginCycle := TRUE;
    END_IF;
  END_IF;
ELSE
  IF Hold THEN
    IF ph = 2 THEN
      acc := T#0s;               (* the interrupted pulse is given again in full *)
    END_IF;
  ELSIF heldPrev AND ph = 2 THEN
    acc := T#0s;                 (* released: the pulse starts now, on for at least this scan *)
  ELSE
    acc := acc + dtScan;
    CASE ph OF
    2:
      IF acc >= Data.set.pulseOn THEN
        acc := T#0s;
        IF pulseNo < ppc THEN
          ph := 3;
        ELSE
          (* the next channel not skipped *)
          nx := 0;
          FOR p := hi - lo + 1 TO ch + 1 BY -1 DO
            IF p > 32 THEN
              nx := p;
            ELSIF (SHR(Data.set.skip, DINT_TO_INT(p - 1)) AND 16#1) = 0 THEN
              nx := p;
            END_IF;
          END_FOR;
          IF nx > 0 THEN
            ch := nx;
            ph := 4;
          ELSE
            (* end of the cycle *)
            CycleDone := TRUE;
            cycles := cycles + 1;
            manual := FALSE;
            IF demandNow OR postLeft > 0 THEN
              ph := 5;
            ELSE
              ph := 0;
            END_IF;
          END_IF;
        END_IF;
      END_IF;
    3:
      IF acc >= Data.set.pulseOff THEN
        acc := T#0s;
        pulseNo := pulseNo + 1;
        ph := 2;
      END_IF;
    4:
      IF acc >= Data.set.channelGap THEN
        acc := T#0s;
        pulseNo := 1;
        ph := 2;
      END_IF;
    5:
      IF acc >= Data.set.cyclePause THEN
        IF demandNow OR manual OR postLeft > 0 THEN
          beginCycle := TRUE;
        ELSE
          ph := 0;
        END_IF;
      END_IF;
    END_CASE;
  END_IF;
END_CASE;

heldPrev := Hold;

IF beginCycle THEN
  (* the first channel not skipped; none = nothing to do *)
  nx := 0;
  FOR p := n TO 1 BY -1 DO
    IF p > 32 THEN
      nx := p;
    ELSIF (SHR(Data.set.skip, DINT_TO_INT(p - 1)) AND 16#1) = 0 THEN
      nx := p;
    END_IF;
  END_FOR;
  IF nx > 0 THEN
    IF NOT demandNow AND NOT manual AND postLeft > 0 THEN
      postLeft := postLeft - 1;  (* a post-clean cycle *)
    END_IF;
    ch := nx;
    pulseNo := 1;
    ph := 2;
    acc := T#0s;
  ELSE
    ph := 0;
    manual := FALSE;
    postLeft := 0;
  END_IF;
END_IF;
IF ph = 0 THEN
  postLeft := 0;
  manual := FALSE;
END_IF;

(* one output at most *)
FOR i := lo TO hi DO
  Outputs[i] := ph = 2 AND NOT Hold AND i - lo + 1 = ch;
END_FOR;

Busy := ph >= 2;
IF ph = 2 OR ph = 3 THEN
  Channel := DINT_TO_INT(ch);
  Data.sts.pulse := pulseNo;
ELSE
  Channel := 0;
  Data.sts.pulse := 0;
END_IF;
IF ph = 4 THEN
  Data.sts.channel := DINT_TO_INT(ch);   (* the channel gap: the channel next *)
ELSE
  Data.sts.channel := Channel;
END_IF;
Data.sts.busy := Busy;
Data.sts.cycles := cycles;
Data.sts.postLeft := postLeft;
Data.sts.configBad := Data.set.pulsesPerChannel < 1 OR Data.set.postCycles < 0 OR Data.set.pulseOn < T#0s OR Data.set.pulseOff < T#0s
                  OR Data.set.channelGap < T#0s OR Data.set.cyclePause < T#0s OR Data.set.startDelay < T#0s;

(* status: the one main thing, in the order config, held, warning, normal,
   idle *)
anyCh := FALSE;
FOR p := 1 TO n DO
  IF p > 32 THEN
    anyCh := TRUE;
  ELSIF (SHR(Data.set.skip, DINT_TO_INT(p - 1)) AND 16#1) = 0 THEN
    anyCh := TRUE;
  END_IF;
  IF anyCh THEN
    EXIT;
  END_IF;
END_FOR;
sf := UT_F_NONE;
IF NOT anyCh THEN
  sc := UT_ST_CONFIG;
  IF n < 1 THEN
    sf := UT_F_NO_OUTPUTS;
  ELSE
    sf := UT_F_ALL_SKIPPED;
  END_IF;
ELSIF Hold AND ph >= 1 THEN
  sc := UT_ST_PAUSED_HOLD;
ELSIF ph = 1 THEN
  sc := UT_ST_START_DELAY;
ELSIF inhibit THEN
  sc := UT_ST_WAIT_DEMAND_DROP;
ELSIF Data.sts.configBad THEN
  sc := UT_ST_WARN_SETTING;
  sf := UT_F_SETTING;
ELSIF ph >= 2 AND ph <= 4 THEN
  sc := UT_ST_CLEANING;          (* channel, pulse and timeLeft say where *)
ELSIF ph = 5 THEN
  sc := UT_ST_CLEAN_NEXT;
ELSIF NOT Enable THEN
  sc := UT_ST_OFF;
ELSE
  sc := UT_ST_IDLE_NO_DEMAND;
END_IF;
(* the time left in the phase, also when the status does not show it *)
CASE ph OF
1: Data.det.timeLeft := Data.set.startDelay - acc;
2: Data.det.timeLeft := Data.set.pulseOn - acc;
3: Data.det.timeLeft := Data.set.pulseOff - acc;
4: Data.det.timeLeft := Data.set.channelGap - acc;
5: Data.det.timeLeft := Data.set.cyclePause - acc;
ELSE
  Data.det.timeLeft := T#0s;
END_CASE;
IF Data.det.timeLeft < T#0s THEN
  Data.det.timeLeft := T#0s;
END_IF;
(* the text is set only when the status changes *)
IF NOT shown OR sc <> shownSt OR sf <> shownF THEN
  shown := TRUE;
  shownSt := sc;
  shownF := sf;
  Data.sts.statusText := UT_STATUS_TEXT(sc, sf);
END_IF;
Data.sts.statusCode := sc;
Data.sts.faultId := sf;
Fault := NOT anyCh;
Warning := Data.sts.configBad;
Data.sts.ne107 := UT_NE107_RUN(Fault := Fault, Check := FALSE, OutOfSpec := Warning, Maint := FALSE);

END_FUNCTION_BLOCK
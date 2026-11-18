(* FB_VesselFlow — what flows into a vessel: the volume's rise per hour plus the metered outflow (a sump's inflow
while its pump empties it, a tank's net fill). An observer: it reads the vessel and the meter, changes nothing.

Pins: ipVessel (the vessel: its volume, never the level, so any shape and level unit works; required), ipOutflow
(optional: the meter on what leaves it, its total in the vessel's volume unit), refData.
Every set.tRateWindow: sts.fRise = the volume's change per hour (negative while it falls), sts.fOutflow = the
meter's rate (0 without one, or while it is bad), sts.fInflow = fRise + fOutflow, all in the vessel's volume unit
per hour. sts.bGood: a whole window of good volume readings (a bad vessel restarts the window; the values hold at
their last good ones). A bad tRateWindow is put back (settings kept over a power cut). *)

FUNCTION_BLOCK FB_VesselFlow EXTENDS FB_Object
  VAR_INPUT
    ipVessel : I_Vessel; (* required *)
    ipOutflow : I_Meter; (* optional *)
    refData : REFERENCE TO ST_VesselFlowData;
  END_VAR
  VAR RETAIN
    stKept : ST_VesselFlowSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    tWindowAt : TIME;
    fWindowVol : REAL;
    bWindowOk : BOOL; (* the window started on a good reading *)
  END_VAR
  VAR_TEMP
    tWin : TIME;
    bVesGood : BOOL;
  END_VAR


IF ipVessel = NULL OR NOT __ISVALIDREF(refData) THEN
  bError := TRUE;
  IF ipVessel = NULL THEN eErrorId := E_UtError.NoMeasurement; ELSE eErrorId := E_UtError.NoRecord; END_IF;
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
  bFirstScan := FALSE;
ELSIF refData.set.tRateWindow > T#0s THEN
  stKept := refData.set;
ELSE
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
END_IF;

bVesGood := ipVessel.bIsGood AND ipVessel.bIsFitted;
IF NOT bVesGood THEN
  bWindowOk := FALSE;             // restart the window when it is good again
  refData.sts.bGood := FALSE;
ELSIF NOT bWindowOk THEN
  tWindowAt := tNow;
  fWindowVol := ipVessel.fActVolume;
  bWindowOk := TRUE;
ELSE
  tWin := tNow - tWindowAt;
  IF tWin >= refData.set.tRateWindow THEN
    refData.sts.fRise := LREAL_TO_REAL(REAL_TO_LREAL(ipVessel.fActVolume - fWindowVol) * 3600000.0
                                        / TIME_TO_LREAL(tWin));
    refData.sts.fOutflow := 0.0;
    IF ipOutflow <> NULL THEN
      IF ipOutflow.bIsGood THEN refData.sts.fOutflow := ipOutflow.fActRate; END_IF;
    END_IF;
    refData.sts.fInflow := refData.sts.fRise + refData.sts.fOutflow;
    refData.sts.bGood := TRUE;
    tWindowAt := tNow;
    fWindowVol := ipVessel.fActVolume;
  END_IF;
END_IF;

bError := FALSE;
bWarning := refData.sts.bRefused;
IF refData.sts.bRefused THEN eErrorId := E_UtError.SettingRefused; ELSE eErrorId := E_UtError.None; END_IF;
IF refData.sts.bGood THEN eState := E_State.Running; ELSE eState := E_State.Idle; END_IF;

END_FUNCTION_BLOCK
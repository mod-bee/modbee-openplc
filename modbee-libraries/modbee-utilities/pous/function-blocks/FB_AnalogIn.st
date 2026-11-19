(* FB_AnalogIn — a raw analog reading (or a remote / computed value) to an engineering value with its health. Wire
the instance to any I_Measurement pin.

Pins: fRawIn (the raw value, e.g. INT_TO_REAL(%IW0); the value itself with Direct), bInputGood (the source is
healthy: IO module, comms, device) -> fValue (engineering value), fPctOfSpan (of the span), bGood, plus
FB_Object's bError / bWarning / eErrorId / eState. refData: its record. stConfig: the engineering constants
(signal type, raw span, unit, custom fail bands), set once at the declaration.

Signal types (stConfig.eSignalType); fRawAtSignalLow / fRawAtSignalHigh are the raw values at the bottom and top of the signal:
  Current4To20  NE43: <= 3.6 mA fail low, 3.6-3.8 under range, 3.8-20.5 measurement, 20.5-21 over range,
                >= 21 fail high
  Current0To20, below 0 % / above 100 % of the span is under / over range (no fail bands: a live zero
  Voltage0To10  is needed to see a wire break)
  Custom        as 0-20 mA, plus fail bands at fCustomFailLowPct / fCustomFailHighPct % of the span
  Direct        fRawIn is already the engineering value (Modbus register, BeeBus value, a calculation): no raw
                scaling; the custom fail bands around fValueAtSignalLow..fValueAtSignalHigh and the trim still apply
A failure (a fail band, not a number, bInputGood FALSE) is ridden through for set.stSignalFault.tTripDelay (the last good
value held, still good, a warning), then per set.stSignalFault: Trip = not good + error, Warn = good (held) + warning,
Signal = not good, no alarm. Under / over range is a warning only. fValue always holds the last good value.
set.bSensorFitted FALSE: this input is not on this site: not good, not fitted, no fault.
Second unit: fValueSecondUnit = fValue * set.fSecondUnitFactor + set.fSecondUnitOffset (bar to psi: factor 14.5038), also in
sts.fValueSecondUnit; it follows fValue (the held value while the signal has failed). A factor or offset that is not a
finite number is a bad setting (put back).
Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.
Placed after it when needed: FB_MeasFilter (filter, low cut-off, clamp), FB_MeasOverride (simulate,
substitute), FB_MeasFrozen (frozen check). *)

FUNCTION_BLOCK FB_AnalogIn EXTENDS FB_Object IMPLEMENTS I_Measurement
  VAR_INPUT
    fRawIn : REAL; (* raw value; the engineering value itself with Direct *)
    bInputGood : BOOL := TRUE; (* the source is healthy (IO module, comms, device) *)
    refData : REFERENCE TO ST_AnalogInData; (* the block's record *)
    stConfig : ST_AnalogInConfig; (* engineering constants (set at the declaration) *)
  END_VAR
  VAR_OUTPUT
    fValue : REAL; (* engineering value; the last good one while the signal has failed *)
    bGood : BOOL; (* fValue is usable *)
    fPctOfSpan : REAL; (* fValue as a % of fValueAtSignalLow..fValueAtSignalHigh *)
    fValueSecondUnit : REAL; (* fValue in the second unit (set.fSecondUnitFactor, fSecondUnitOffset) *)
  END_VAR
  VAR RETAIN
    stKept : ST_AnalogInSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
  END_VAR
  VAR
    stWFault : ST_ProtectionWork;
    bHaveGood : BOOL; (* a good value has been read since power-up *)
    bFittedNow : BOOL;
    bTripWas : BOOL;
    eFirst : E_UtError; (* the cause when the fault tripped (first-out) *)
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    bCfgOk : BOOL;
    bReset : BOOL;
    bNaN : BOOL;
    bFailing : BOOL;
    bTrip : BOOL;
    fSpan : REAL;
    fPos : REAL;
    fEng : REAL;
    fPct : REAL;
    eSig : E_AiStatus;
    eCause : E_UtError;
  END_VAR


PROPERTY PUBLIC fActValue : REAL    // the value in its unit (held at the last good one while bad, when so set)
   GET
     fActValue := fValue;
   END_GET
 END_PROPERTY
 PROPERTY PUBLIC bIsGood : BOOL    // the value can be trusted now
   GET
     bIsGood := bGood;
   END_GET
 END_PROPERTY
 PROPERTY PUBLIC bHasValue : BOOL    // a continuous value (FALSE: switches only)
   GET
     bHasValue := TRUE;
   END_GET
 END_PROPERTY
 PROPERTY PUBLIC bIsFitted : BOOL    // the sensor is on this site (FALSE: no value, no bands, no fault)
   GET
     bIsFitted := bFittedNow;
   END_GET
 END_PROPERTY
 PROPERTY PUBLIC eUnit : E_Unit    // the unit of the value
   GET
     eUnit := stConfig.eUnit;
   END_GET
 END_PROPERTY
 (* an analog input has no switch bands
(FB_LevelCheck compares its value) *)
 METHOD PUBLIC Band : BOOL
   VAR_INPUT
     eBand : E_Band;    // the band asked about (LowLow, Low, High, HighHigh); returns TRUE while the value is in it
   END_VAR
   Band := FALSE;
 END_METHOD

 METHOD PRIVATE ProtOk : BOOL
   VAR_INPUT
     stP : REFERENCE TO ST_ProtectionSet;
   END_VAR
   ProtOk := stP.tTripDelay >= T#0s AND stP.tAutoRecoverAfter >= T#0s AND stP.nMaxRetriesBeforeLockout >= 0;
 END_METHOD

 (* the settings are usable *)
 METHOD PRIVATE SetWhy : E_UtError
   VAR_INPUT
     stS : REFERENCE TO ST_AnalogInSet;
   END_VAR
   SetWhy := E_UtError.None;
   IF NOT (ABS(stS.fValueAtSignalHigh - stS.fValueAtSignalLow) > 0.0) THEN   // no span
     SetWhy := E_UtError.LimitsBad;
   ELSIF NOT (ABS(stS.fValueAtSignalHigh - stS.fValueAtSignalLow) <= 3.4E38) THEN
     SetWhy := E_UtError.ValueBad;
   ELSIF NOT (ABS(stS.fZeroTrim) <= 3.4E38) THEN
     SetWhy := E_UtError.ValueBad;
   ELSIF NOT (ABS(stS.fSecondUnitFactor) <= 3.4E38) THEN
     SetWhy := E_UtError.ValueBad;
   ELSIF NOT (ABS(stS.fSecondUnitOffset) <= 3.4E38) THEN
     SetWhy := E_UtError.ValueBad;
   ELSIF NOT (ProtOk(stP := stS.stSignalFault)) THEN
     SetWhy := E_UtError.ProtectionBad;
   ELSIF NOT (stS.tRetryCountWindow >= T#0s) THEN
     SetWhy := E_UtError.TimeBad;
   END_IF;
 END_METHOD

 METHOD PRIVATE SetOk : BOOL
   VAR_INPUT
     stS : REFERENCE TO ST_AnalogInSet;
   END_VAR
   SetOk := SetWhy(stS := stS) = E_UtError.None;
 END_METHOD

 (* the engineering constants are usable *)
 METHOD PRIVATE CfgOk : BOOL
   CASE stConfig.eSignalType OF
     E_AiSignal.Current4To20, E_AiSignal.Current0To20, E_AiSignal.Voltage0To10, E_AiSignal.Custom:
       CfgOk := ABS(stConfig.fRawAtSignalHigh - stConfig.fRawAtSignalLow) > 0.0
                AND ABS(stConfig.fRawAtSignalHigh - stConfig.fRawAtSignalLow) <= 3.4E38;
     E_AiSignal.Direct:
       CfgOk := TRUE;
   ELSE
     CfgOk := FALSE;
   END_CASE;
   IF stConfig.eSignalType = E_AiSignal.Custom OR stConfig.eSignalType = E_AiSignal.Direct THEN
     CfgOk := CfgOk AND stConfig.fCustomFailLowPct < stConfig.fCustomFailHighPct;
   END_IF;
 END_METHOD

 IF NOT __ISVALIDREF(refData) THEN
   bGood := FALSE;
   bFittedNow := FALSE;
   bError := TRUE;
   eErrorId := E_UtError.NoRecord;
   eState := E_State.Fault;
   RETURN;
 END_IF;
 tNow := TIME();

 (* kept settings; a bad write is put back *)
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
   refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
   refData.set := stKept;
   refData.sts.bSettingRefused := TRUE;
   bOk := TRUE;
 END_IF;
 bCfgOk := CfgOk();
 bOk := bOk AND bCfgOk;

 bReset := SystemReset();
 IF refData.bCmdResetFaults THEN
   bReset := TRUE;
   refData.bCmdResetFaults := FALSE;
   refData.sts.bSettingRefused := FALSE;
   refData.sts.eSettingRefusedErrorId := E_UtError.None;
 END_IF;
 bFittedNow := refData.set.bSensorFitted;

 (* scaling and the signal checks *)
 refData.det.fRawValue := fRawIn;
 bNaN := NOT (ABS(fRawIn) <= 3.4E38);
 eSig := E_AiStatus.Ok;
 fEng := 0.0;
 fSpan := refData.set.fValueAtSignalHigh - refData.set.fValueAtSignalLow;
 IF bOk AND NOT bNaN THEN
   IF stConfig.eSignalType = E_AiSignal.Direct THEN
     fEng := fRawIn;
     fPos := (fRawIn - refData.set.fValueAtSignalLow) / fSpan;
   ELSE
     fPos := (fRawIn - stConfig.fRawAtSignalLow) / (stConfig.fRawAtSignalHigh - stConfig.fRawAtSignalLow);
     fEng := refData.set.fValueAtSignalLow + fPos * fSpan;
   END_IF;
   fEng := fEng + refData.set.fZeroTrim;
   CASE stConfig.eSignalType OF
     E_AiSignal.Current0To20, E_AiSignal.Voltage0To10:
       IF fPos < 0.0 THEN
         eSig := E_AiStatus.UnderRange;
       ELSIF fPos > 1.0 THEN
         eSig := E_AiStatus.OverRange;
       END_IF;
     E_AiSignal.Custom, E_AiSignal.Direct:
       fPct := fPos * 100.0;
       IF fPct <= stConfig.fCustomFailLowPct THEN
         eSig := E_AiStatus.FailLow;
       ELSIF fPct >= stConfig.fCustomFailHighPct THEN
         eSig := E_AiStatus.FailHigh;
       ELSIF fPos < 0.0 THEN
         eSig := E_AiStatus.UnderRange;
       ELSIF fPos > 1.0 THEN
         eSig := E_AiStatus.OverRange;
       END_IF;
   ELSE
     (* NE43, as a fraction of the 16 mA span: 3.6 mA = -0.025, 3.8 mA = -0.0125, 20.5 mA = 1.03125,
        21 mA = 1.0625 *)
     IF fPos <= -0.025 THEN
       eSig := E_AiStatus.FailLow;
     ELSIF fPos < -0.0125 THEN
       eSig := E_AiStatus.UnderRange;
     ELSIF fPos >= 1.0625 THEN
       eSig := E_AiStatus.FailHigh;
     ELSIF fPos > 1.03125 THEN
       eSig := E_AiStatus.OverRange;
     END_IF;
   END_CASE;
 END_IF;
 IF NOT bInputGood THEN
   eSig := E_AiStatus.InputBad;
 ELSIF bNaN THEN
   eSig := E_AiStatus.FailLow;
 END_IF;
 bFailing := eSig = E_AiStatus.FailLow OR eSig = E_AiStatus.FailHigh OR eSig = E_AiStatus.InputBad;
 IF NOT bFittedNow THEN
   eSig := E_AiStatus.NotFitted;
   bFailing := FALSE;
 END_IF;

 (* the fault: ridden through for its delay *)
 bTrip := F_Protect(tNow := tNow, bConditionPresent := bFailing AND bOk, bResetRequest := bReset,
                    tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stSignalFault,
                    stStatus := refData.sts.stSignalFault, stWorking := stWFault);

 (* the value: the last good one is held *)
 IF bOk AND bFittedNow AND NOT bFailing THEN
   fValue := fEng;
   bHaveGood := TRUE;
 END_IF;
 IF bOk THEN
   fPctOfSpan := (fValue - refData.set.fValueAtSignalLow) / fSpan * 100.0;
 ELSE
   fPctOfSpan := 0.0;
 END_IF;
 bGood := bOk AND bFittedNow AND bHaveGood AND NOT bTrip AND NOT stWFault.bSignalling;

 (* errors *)
 CASE eSig OF
   E_AiStatus.FailLow, E_AiStatus.UnderRange:
     eCause := E_UtError.SignalLow;
   E_AiStatus.FailHigh, E_AiStatus.OverRange:
     eCause := E_UtError.SignalHigh;
   E_AiStatus.InputBad:
     eCause := E_UtError.SensorBad;
 ELSE
   eCause := E_UtError.None;
 END_CASE;
 IF bTrip AND NOT bTripWas THEN
   eFirst := eCause;
   IF eFirst = E_UtError.None THEN
     eFirst := E_UtError.SensorBad;
   END_IF;
 END_IF;
 bTripWas := bTrip;
 bError := NOT bOk OR bTrip;
 bWarning := NOT bError AND ((eCause <> E_UtError.None AND NOT stWFault.bSignalling) OR stWFault.bWarning
                             OR stWFault.bSettingBad OR refData.sts.bSettingRefused);

 IF NOT bOk THEN
   eErrorId := E_UtError.BadSetting;
 ELSIF bTrip THEN
   eErrorId := eFirst;
 ELSIF eCause <> E_UtError.None AND NOT stWFault.bSignalling THEN
   eErrorId := eCause;
 ELSIF stWFault.bSettingBad THEN
   eErrorId := E_UtError.BadSetting;
 ELSIF refData.sts.bSettingRefused THEN
   eErrorId := E_UtError.SettingRefused;
 ELSE
   eErrorId := E_UtError.None;
 END_IF;
 IF bError THEN
   eState := E_State.Fault;
 ELSIF NOT bFittedNow THEN
   eState := E_State.Off;
 ELSIF NOT bHaveGood THEN
   eState := E_State.Waiting;
 ELSIF bFailing OR stWFault.bSignalling THEN
   eState := E_State.Held;
 ELSE
   eState := E_State.Running;
 END_IF;

 fValueSecondUnit := fValue * refData.set.fSecondUnitFactor + refData.set.fSecondUnitOffset;
 refData.sts.fValue := fValue;
 refData.sts.fValueSecondUnit := fValueSecondUnit;
 refData.sts.bGood := bGood;
 refData.sts.eSignalStatus := eSig;
 refData.det.fPctOfSpan := fPctOfSpan;
 bFirstScan := FALSE;

END_FUNCTION_BLOCK
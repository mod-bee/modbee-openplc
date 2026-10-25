(* The settings check of UT_ANALOG_IN: TRUE when all are usable; Id = the first that is not *)

FUNCTION UT_ANALOG_CHECK : BOOL
  VAR_IN_OUT
    Set : UT_ANALOG_SET;
  END_VAR
  VAR_OUTPUT
    Id : UT_FAULT;
    SpanBad : BOOL; (* the value cannot be worked out *)
    Warn : BOOL; (* a display-only setting *)
  END_VAR


Id := UT_F_NONE;
SpanBad := NOT (Set.signal = UT_AI_4_20MA OR Set.signal = UT_AI_0_20MA OR Set.signal = UT_AI_0_10V
                OR Set.signal = UT_AI_CUSTOM OR Set.signal = UT_AI_DIRECT)
           OR NOT (ABS(Set.engMax - Set.engMin) > 0.0 AND ABS(Set.engMax - Set.engMin) <= 3.4E38)
           OR (Set.signal <> UT_AI_DIRECT
               AND NOT (ABS(Set.rawMax - Set.rawMin) > 0.0 AND ABS(Set.rawMax - Set.rawMin) <= 3.4E38));
Warn := NOT (ABS(Set.trimOffset) <= 3.4E38) OR NOT (ABS(Set.altFactor) <= 3.4E38) OR NOT (ABS(Set.altOffset) <= 3.4E38);
IF SpanBad THEN
  Id := UT_F_ENG_MIN_MAX;
ELSIF Warn THEN
  Id := UT_F_SETTING;
ELSIF Set.filterTime < T#0s OR NOT (ABS(Set.lowCutoff) <= 3.4E38)
      OR NOT (Set.customLowFail < Set.customHighFail) OR NOT (ABS(Set.substValue) <= 3.4E38)
      OR NOT (Set.frozenBand >= 0.0 AND Set.frozenBand <= 3.4E38) OR Set.retryWindow < T#0s
      OR NOT (Set.faultAction = UT_AI_HOLD OR Set.faultAction = UT_AI_MIN OR Set.faultAction = UT_AI_MAX
              OR Set.faultAction = UT_AI_SUBST OR Set.faultAction = UT_AI_PASS) THEN
  Id := UT_F_SETTING;
  Warn := TRUE;
END_IF;
UT_ANALOG_CHECK := Id = UT_F_NONE;

END_FUNCTION
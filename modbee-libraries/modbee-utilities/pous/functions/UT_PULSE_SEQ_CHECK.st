FUNCTION UT_PULSE_SEQ_CHECK : BOOL
  VAR_IN_OUT
    S : UT_PULSE_SEQ_SET;
  END_VAR

UT_PULSE_SEQ_CHECK := S.pulsesPerChannel >= 1 AND S.postCycles >= 0 AND S.pulseOn >= T#0s AND S.pulseOff >= T#0s
                      AND S.channelGap >= T#0s AND S.cyclePause >= T#0s AND S.startDelay >= T#0s;

END_FUNCTION
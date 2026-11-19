(* Calibrates one analog channel, and keeps it across a power cut.

eChannel    which channel.
              UIO_AI01, UIO_AI02, UIO_AI03, UIO_AI04
              UIO_AO01, UIO_AO02
fOffset     added to the reading after scaling, in volts or milliamps.
nZeroCount  converter count that reads 0 V or 0 mA, 0 to 32767.
nFullScaleCount  converter count that reads full scale: 10 V or 20 mA.
bApplyCalibration       one shot, use fOffset, nZeroCount and nFullScaleCount now.
bSaveToFlash  one shot, write every channel to flash.
bResetAllToDefaults  one shot, defaults everywhere, and save.

fOffsetInUse  what eChannel currently holds.
nZeroCountInUse     the same, for nZeroCount.
nFullScaleCountInUse    the same, for nFullScaleCount.
bSaveDone   one scan, when a write succeeded.
bError      the last request failed.
eErrorId    why.
              UIO_OK, UIO_NOT_READY, UIO_INVALID_ARGUMENT, UIO_IO_ERROR,
              UIO_NO_DATA, UIO_TOO_LARGE, UIO_UNSUPPORTED

---

Two points and an offset per channel. The two counts are the converter's own
numbers at 0 and at full scale (10 V or 20 mA); the offset trims the result afterwards
in engineering units. Leaving the counts equal falls back to a straight ratio,
which is what an uncalibrated channel does.

To calibrate AI01:

  1. Apply 0 V (0 mA on a current input) and read nAI01RawCount. That is nZeroCount.
  2. Apply 10 V (20 mA) and read nAI01RawCount. That is nFullScaleCount.
  3. Set eChannel, the two counts and fOffset := 0.0, then pulse bApplyCalibration.
  4. Check AI01 reads what you applied.
  5. Pulse bSaveToFlash.

bApplyCalibration takes effect at once but only in RAM, so values can be tried freely.
Nothing reaches flash except on bSaveToFlash or bResetAllToDefaults, so holding bApplyCalibration costs nothing.

Work one channel at a time. bResetAllToDefaults puts every channel back to its default and
saves that, which is the way back from a calibration gone wrong. *)

FUNCTION_BLOCK FB_AnalogCalibration
  VAR_INPUT
    eChannel : E_AnalogChannel; (* which channel to calibrate: UIO_AI01..UIO_AI04, UIO_AO01, UIO_AO02 *)
    fOffset : REAL; (* added to the reading after scaling, volts or milliamps *)
    nZeroCount : INT; (* converter count that reads 0 V or 0 mA, 0..32767 (the code scales (raw - nZeroCount) x full / (nFullScaleCount - nZeroCount), full = 10 V or 20 mA); not the 4 mA point *)
    nFullScaleCount : INT; (* converter count that reads full scale: 10 V or 20 mA *)
    bApplyCalibration : BOOL; (* rising edge: use fOffset and the two counts now, in RAM only *)
    bSaveToFlash : BOOL; (* rising edge: write every channel's calibration to flash *)
    bResetAllToDefaults : BOOL; (* rising edge: every channel back to its default, and saved *)
  END_VAR
  VAR_OUTPUT
    fOffsetInUse : REAL; (* the offset eChannel uses now *)
    nZeroCountInUse : INT; (* the zero count eChannel uses now *)
    nFullScaleCountInUse : INT; (* the full-scale count eChannel uses now *)
    bSaveDone : BOOL; (* one scan, when a write to flash succeeded *)
    bError : BOOL; (* the last request failed *)
    eErrorId : E_UioResult; (* why; UIO_OK when fine *)
  END_VAR
  VAR
    lastApply : BOOL;
    lastSave : BOOL;
    lastReset : BOOL;
  END_VAR
#include <NodeUioAPI.h>

E_UIORESULT uio_status(UioResult result);

// E_AnalogChannel lists the four inputs first, then the two outputs, so the
// ordinal separates them and indexes within the group.
static bool uio_cal_is_output(uint8_t channel)
{
  return channel >= UIO_ANALOG_INPUTS;
}

static uint8_t uio_cal_index(uint8_t channel)
{
  return uio_cal_is_output(channel) ? (uint8_t)(channel - UIO_ANALOG_INPUTS) : channel;
}

void setup()
{
  fOffsetInUse = 0.0;
  nZeroCountInUse = 0;
  nFullScaleCountInUse = 0;
  bSaveDone = false;
  bError = false;
  eErrorId = E_UIORESULT::UIO_OK;
  lastApply = false;
  lastSave = false;
  lastReset = false;
}

void loop()
{
  const uint8_t channel = (uint8_t)(E_ANALOGCHANNEL)eChannel;
  const uint8_t index = uio_cal_index(channel);
  const bool isOutput = uio_cal_is_output(channel);

  bSaveDone = false;
  UioResult result = UIO_OK;

  if ((bool)bApplyCalibration && !(bool)lastApply) {
    UioCalibration cal;
    cal.offset = (float)fOffset;
    cal.low = (int16_t)nZeroCount;
    cal.high = (int16_t)nFullScaleCount;
    result = isOutput ? uio().setOutputCalibration(index, cal)
                      : uio().setInputCalibration(index, cal);
  }
  lastApply = (bool)bApplyCalibration;

  if ((bool)bResetAllToDefaults && !(bool)lastReset) {
    result = uio().resetCalibration();
    bSaveDone = (result == UIO_OK);
  }
  lastReset = (bool)bResetAllToDefaults;

  if ((bool)bSaveToFlash && !(bool)lastSave) {
    result = uio().saveCalibration();
    bSaveDone = (result == UIO_OK);
  }
  lastSave = (bool)bSaveToFlash;

  UioCalibration now;
  const UioResult read = isOutput ? uio().outputCalibration(index, now)
                                  : uio().inputCalibration(index, now);
  if (read == UIO_OK) {
    fOffsetInUse = now.offset;
    nZeroCountInUse = now.low;
    nFullScaleCountInUse = now.high;
  } else if (result == UIO_OK) {
    result = read;
  }

  bError = (result != UIO_OK);
  eErrorId = uio_status(result);
}

END_FUNCTION_BLOCK
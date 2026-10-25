(* Calibrates one analog channel, and keeps it across a power cut.

CHANNEL     which channel.
              UIO_AI01, UIO_AI02, UIO_AI03, UIO_AI04
              UIO_AO01, UIO_AO02
OFFSET      added to the reading after scaling, in volts or milliamps.
LOW_COUNT   converter count at the bottom of the range, 0 to 32767.
HIGH_COUNT  converter count at the top.
APPLY       one shot, use OFFSET, LOW_COUNT and HIGH_COUNT now.
SAVE        one shot, write every channel to flash.
RESET       one shot, defaults everywhere, and save.

OFFSET_NOW  what CHANNEL currently holds.
LOW_NOW     the same, for LOW_COUNT.
HIGH_NOW    the same, for HIGH_COUNT.
SAVED       one scan, when a write succeeded.
ERROR       the last request failed.
STATUS      why.
              UIO_OK, UIO_NOT_READY, UIO_INVALID_ARGUMENT, UIO_IO_ERROR,
              UIO_NO_DATA, UIO_TOO_LARGE, UIO_UNSUPPORTED

---

Two points and an offset per channel. The two counts say where the range starts
and ends in the converter's own numbers; the offset trims the result afterwards
in engineering units. Leaving the counts equal falls back to a straight ratio,
which is what an uncalibrated channel does.

To calibrate AI01:

  1. Apply a known bottom-of-range signal and read AI01_RAW. That is LOW_COUNT.
  2. Apply a known top-of-range signal and read AI01_RAW. That is HIGH_COUNT.
  3. Set CHANNEL, the two counts and OFFSET := 0.0, then pulse APPLY.
  4. Check AI01 reads what you applied.
  5. Pulse SAVE.

APPLY takes effect at once but only in RAM, so values can be tried freely.
Nothing reaches flash except on SAVE or RESET, so holding APPLY costs nothing.

Work one channel at a time. RESET puts every channel back to its default and
saves that, which is the way back from a calibration gone wrong. *)

FUNCTION_BLOCK ANALOG_CAL
  VAR_INPUT
    CHANNEL : UIO_CHANNEL;
    OFFSET : REAL;
    LOW_COUNT : INT;
    HIGH_COUNT : INT;
    APPLY : BOOL;
    SAVE : BOOL;
    RESET : BOOL;
  END_VAR
  VAR_OUTPUT
    OFFSET_NOW : REAL;
    LOW_NOW : INT;
    HIGH_NOW : INT;
    SAVED : BOOL;
    ERROR : BOOL;
    STATUS : UIO_RESULT;
  END_VAR
  VAR
    lastApply : BOOL;
    lastSave : BOOL;
    lastReset : BOOL;
  END_VAR
#include <NodeUioAPI.h>

UIO_RESULT uio_status(UioResult result);

// UIO_CHANNEL lists the four inputs first, then the two outputs, so the
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
  OFFSET_NOW = 0.0;
  LOW_NOW = 0;
  HIGH_NOW = 0;
  SAVED = false;
  ERROR = false;
  STATUS = UIO_RESULT::UIO_OK;
  lastApply = false;
  lastSave = false;
  lastReset = false;
}

void loop()
{
  const uint8_t channel = (uint8_t)(UIO_CHANNEL)CHANNEL;
  const uint8_t index = uio_cal_index(channel);
  const bool isOutput = uio_cal_is_output(channel);

  SAVED = false;
  UioResult result = UIO_OK;

  if ((bool)APPLY && !(bool)lastApply) {
    UioCalibration cal;
    cal.offset = (float)OFFSET;
    cal.low = (int16_t)LOW_COUNT;
    cal.high = (int16_t)HIGH_COUNT;
    result = isOutput ? uio().setOutputCalibration(index, cal)
                      : uio().setInputCalibration(index, cal);
  }
  lastApply = (bool)APPLY;

  if ((bool)RESET && !(bool)lastReset) {
    result = uio().resetCalibration();
    SAVED = (result == UIO_OK);
  }
  lastReset = (bool)RESET;

  if ((bool)SAVE && !(bool)lastSave) {
    result = uio().saveCalibration();
    SAVED = (result == UIO_OK);
  }
  lastSave = (bool)SAVE;

  UioCalibration now;
  const UioResult read = isOutput ? uio().outputCalibration(index, now)
                                  : uio().inputCalibration(index, now);
  if (read == UIO_OK) {
    OFFSET_NOW = now.offset;
    LOW_NOW = now.low;
    HIGH_NOW = now.high;
  } else if (result == UIO_OK) {
    result = read;
  }

  ERROR = (result != UIO_OK);
  STATUS = uio_status(result);
}

END_FUNCTION_BLOCK
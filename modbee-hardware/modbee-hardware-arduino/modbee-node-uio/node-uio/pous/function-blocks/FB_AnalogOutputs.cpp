(* Drives the two analog outputs.

eAO01Mode, eAO02Mode  what the channel is wired for.
                        UIO_VOLTAGE   0-10 V
                        UIO_CURRENT   0-20 mA

fAO01, fAO02            the value to output, in volts or milliamps.

nAO01RawCount, nAO02RawCount    the converter count it became, 0 to 32767.

---

The value is in engineering units: 5.0 on a voltage channel is 5 V, and 12.0 on
a current one is 12 mA. Anything past the end of the range is held there rather
than wrapping.

As with the inputs, the mode pin only changes the arithmetic; the terminal is
decided by a solder bridge. The board ships with the outputs bridged for 0-10 V.

The converter is only written when the value changes, so holding a setpoint
costs nothing on the I2C bus. *)

FUNCTION_BLOCK FB_AnalogOutputs
  VAR_INPUT
    eAO01Mode : E_AnalogMode; (* fAO01 wired for UIO_VOLTAGE (0-10 V) or UIO_CURRENT (0-20 mA); must match the solder bridge *)
    eAO02Mode : E_AnalogMode; (* fAO02 wiring mode *)
    fAO01 : REAL; (* fAO01 output in volts or milliamps; held at the range ends *)
    fAO02 : REAL; (* fAO02 output in volts or milliamps *)
  END_VAR
  VAR_OUTPUT
    nAO01RawCount : INT; (* the converter count fAO01 became, 0..32767 *)
    nAO02RawCount : INT; (* the converter count fAO02 became *)
  END_VAR
#include <NodeUioAPI.h>

static int16_t uio_aout_raw(uint8_t channel)
{
  int16_t value = 0;
  return uio().analogOutRaw(channel, value) == UIO_OK ? value : 0;
}

void setup()
{
  nAO01RawCount = 0;
  nAO02RawCount = 0;
}

void loop()
{
  uio().setOutputRange(0, (UioRange)(E_ANALOGMODE)eAO01Mode);
  uio().setOutputRange(1, (UioRange)(E_ANALOGMODE)eAO02Mode);

  uio().setAnalogOut(0, (float)fAO01);
  uio().setAnalogOut(1, (float)fAO02);

  nAO01RawCount = uio_aout_raw(0);
  nAO02RawCount = uio_aout_raw(1);
}

END_FUNCTION_BLOCK
(* Drives the two analog outputs.

AO01_MODE, AO02_MODE  what the channel is wired for.
                        UIO_VOLTAGE   0-10 V
                        UIO_CURRENT   0-20 mA

AO01, AO02            the value to output, in volts or milliamps.

AO01_RAW, AO02_RAW    the converter count it became, 0 to 32767.

---

The value is in engineering units: 5.0 on a voltage channel is 5 V, and 12.0 on
a current one is 12 mA. Anything past the end of the range is held there rather
than wrapping.

As with the inputs, the mode pin only changes the arithmetic; the terminal is
decided by a solder bridge. The board ships with the outputs bridged for 0-10 V.

The converter is only written when the value changes, so holding a setpoint
costs nothing on the I2C bus. *)

FUNCTION_BLOCK ANALOG_OUT
  VAR_INPUT
    AO01_MODE : UIO_MODE;
    AO02_MODE : UIO_MODE;
    AO01 : REAL;
    AO02 : REAL;
  END_VAR
  VAR_OUTPUT
    AO01_RAW : INT;
    AO02_RAW : INT;
  END_VAR
#include <NodeUioAPI.h>

static int16_t uio_aout_raw(uint8_t channel)
{
  int16_t value = 0;
  return uio().analogOutRaw(channel, value) == UIO_OK ? value : 0;
}

void setup()
{
  AO01_RAW = 0;
  AO02_RAW = 0;
}

void loop()
{
  uio().setOutputRange(0, (UioRange)(UIO_MODE)AO01_MODE);
  uio().setOutputRange(1, (UioRange)(UIO_MODE)AO02_MODE);

  uio().setAnalogOut(0, (float)AO01);
  uio().setAnalogOut(1, (float)AO02);

  AO01_RAW = uio_aout_raw(0);
  AO02_RAW = uio_aout_raw(1);
}

END_FUNCTION_BLOCK
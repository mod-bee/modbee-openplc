(* Reads the four analog inputs.

AI01_MODE..AI04_MODE  what the channel is wired for.
                        UIO_VOLTAGE   0-10 V
                        UIO_CURRENT   0-20 mA

AI01..AI04            the reading, in volts or milliamps. A saturated input
                        reads 11 V / 22 mA.
AI01_RAW..AI04_RAW    the converter count behind it, 0 to 32767.

---

The reading is in engineering units: volts on a voltage channel, milliamps on a
current one. 5 V reads 5.0, and 12 mA reads 12.0. Scale it to whatever the
sensor measures in your own program.

An input beyond what the converter can measure (a shorted 4-20 mA transmitter,
a sensor failed high) saturates it, and then reads 22.0 mA on a current channel
or 11.0 V on a voltage one: clearly over range, so transmitter-failed-high
detection (NAMUR NE43, from 21 mA) works. Saturation is judged on the raw count
(32765 or more), before calibration. Below the range a reading is 0.

The raw count is the converter's own number, before scaling and before
calibration. You need it to calibrate a channel, and to tell a reading that is
wrong because of the scaling from one that is wrong at the terminal.

The mode pin only changes the arithmetic. Which signal a terminal actually
accepts is a solder bridge on the board, and the board ships with the inputs
bridged for 0-20 mA. A channel bridged for current and left on UIO_VOLTAGE
gives a confident wrong number rather than an error.

The four channels share one converter and are read in turn, so any one of them
refreshes about every 20 ms however fast the task runs. Reading a channel twice
in a scan gives the same number twice. *)

FUNCTION_BLOCK ANALOG_IN
  VAR_INPUT
    AI01_MODE : UIO_MODE;
    AI02_MODE : UIO_MODE;
    AI03_MODE : UIO_MODE;
    AI04_MODE : UIO_MODE;
  END_VAR
  VAR_OUTPUT
    AI01 : REAL;
    AI02 : REAL;
    AI03 : REAL;
    AI04 : REAL;
    AI01_RAW : INT;
    AI02_RAW : INT;
    AI03_RAW : INT;
    AI04_RAW : INT;
  END_VAR
#include <NodeUioAPI.h>

static float uio_ain(uint8_t channel)
{
  float value = 0.0f;
  return uio().analogIn(channel, value) == UIO_OK ? value : 0.0f;
}

static int16_t uio_ain_raw(uint8_t channel)
{
  int16_t value = 0;
  return uio().analogInRaw(channel, value) == UIO_OK ? value : 0;
}

void setup()
{
  AI01 = 0.0;
  AI02 = 0.0;
  AI03 = 0.0;
  AI04 = 0.0;
  AI01_RAW = 0;
  AI02_RAW = 0;
  AI03_RAW = 0;
  AI04_RAW = 0;
}

void loop()
{
  uio().setInputRange(0, (UioRange)(UIO_MODE)AI01_MODE);
  uio().setInputRange(1, (UioRange)(UIO_MODE)AI02_MODE);
  uio().setInputRange(2, (UioRange)(UIO_MODE)AI03_MODE);
  uio().setInputRange(3, (UioRange)(UIO_MODE)AI04_MODE);

  AI01 = uio_ain(0);
  AI02 = uio_ain(1);
  AI03 = uio_ain(2);
  AI04 = uio_ain(3);

  AI01_RAW = uio_ain_raw(0);
  AI02_RAW = uio_ain_raw(1);
  AI03_RAW = uio_ain_raw(2);
  AI04_RAW = uio_ain_raw(3);
}

END_FUNCTION_BLOCK
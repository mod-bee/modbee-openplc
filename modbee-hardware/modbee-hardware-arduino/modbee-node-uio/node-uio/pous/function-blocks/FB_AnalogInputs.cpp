(* Reads the four analog inputs.

eAI01Mode..eAI04Mode  what the channel is wired for.
                        UIO_VOLTAGE   0-10 V
                        UIO_CURRENT   0-20 mA

fAI01..fAI04            the reading, in volts or milliamps. A saturated input
                        reads 11 V / 22 mA.
nAI01RawCount..nAI04RawCount    the converter count behind it, 0 to 32767.

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

FUNCTION_BLOCK FB_AnalogInputs
  VAR_INPUT
    eAI01Mode : E_AnalogMode; (* fAI01 wired for UIO_VOLTAGE (0-10 V) or UIO_CURRENT (0-20 mA); must match the solder bridge *)
    eAI02Mode : E_AnalogMode; (* fAI02 wiring mode *)
    eAI03Mode : E_AnalogMode; (* fAI03 wiring mode *)
    eAI04Mode : E_AnalogMode; (* fAI04 wiring mode *)
  END_VAR
  VAR_OUTPUT
    fAI01 : REAL; (* fAI01 reading in volts or milliamps; over range reads 11 V / 22 mA *)
    fAI02 : REAL; (* fAI02 reading in volts or milliamps *)
    fAI03 : REAL; (* fAI03 reading in volts or milliamps *)
    fAI04 : REAL; (* fAI04 reading in volts or milliamps *)
    nAI01RawCount : INT; (* fAI01 converter count before scaling and calibration, 0..32767 *)
    nAI02RawCount : INT; (* fAI02 converter count *)
    nAI03RawCount : INT; (* fAI03 converter count *)
    nAI04RawCount : INT; (* fAI04 converter count *)
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
  fAI01 = 0.0;
  fAI02 = 0.0;
  fAI03 = 0.0;
  fAI04 = 0.0;
  nAI01RawCount = 0;
  nAI02RawCount = 0;
  nAI03RawCount = 0;
  nAI04RawCount = 0;
}

void loop()
{
  uio().setInputRange(0, (UioRange)(E_ANALOGMODE)eAI01Mode);
  uio().setInputRange(1, (UioRange)(E_ANALOGMODE)eAI02Mode);
  uio().setInputRange(2, (UioRange)(E_ANALOGMODE)eAI03Mode);
  uio().setInputRange(3, (UioRange)(E_ANALOGMODE)eAI04Mode);

  fAI01 = uio_ain(0);
  fAI02 = uio_ain(1);
  fAI03 = uio_ain(2);
  fAI04 = uio_ain(3);

  nAI01RawCount = uio_ain_raw(0);
  nAI02RawCount = uio_ain_raw(1);
  nAI03RawCount = uio_ain_raw(2);
  nAI04RawCount = uio_ain_raw(3);
}

END_FUNCTION_BLOCK
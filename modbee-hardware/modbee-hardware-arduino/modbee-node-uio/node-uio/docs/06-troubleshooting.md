# 06 - Troubleshooting

## `READY` never goes true

`STATUS` on the `UIO` block says which part did not answer.

`UIO_NOT_READY` means the ADC, the DAC, or both did not respond on I2C. They
share one bus, so a single stuck device takes out both. Power the board down and
back up rather than resetting it — an I2C device held mid-transaction stays that
way through a reset.

If it persists, it is the board rather than the program.

## An analog reading is steady but wrong

Almost always the mode and the solder bridge disagree. Check what the channel is
bridged for and what your program passes to `CH0n_MODE`. A channel bridged for
voltage and told `UIO_CURRENT` reads about half what it should, convincingly.

If they agree, look at `AI0n_RAW`. A raw count that moves sensibly with the
input means the scaling or the calibration is wrong. A raw count stuck at 0 or
32767 means the input is outside what the converter can see.

## An analog reading will not settle

The four inputs share one converter and are read in turn, so any channel
refreshes about every 20 ms. Sampling faster than that in your program gives you
the same number several times, not a faster signal.

If the value is genuinely noisy, the cause is upstream: shielding, cable length,
or a shared ground. Average it in your own program.

## An output does nothing

There is no fault feedback on this board, so an output that is shorted, open or
unpowered reads exactly like one that is working.

Check the load is between the switched supply and the output pin, not between
the output and ground — these are open-drain drivers, not push-pull. Then check
the group's supply, since the outputs are in two isolated groups.

## Outputs turn off when the board sleeps

Expected on deep sleep, for DO05 to DO08 — they are outside the RTC domain and
cannot be held. See [04 Sleep](04-sleep.md).

If DO01 to DO04 also dropped, their `DO0n_IN_SLEEP` pins were false, which is
what they are for — set the one you need true.

## Retained values are gone after a restart

Check **Persistent Storage** is switched on in the project's device settings.
Off, nothing is stored and every retained variable starts at its declared
initial value on every start.

If you changed a retained variable itself — added one, or changed its type —
that one starts at its initial value; that is deliberate. A damaged stored copy
is refused whole. See [05 Retained variables](05-retained-variables.md).

If you only changed the logic, the values should have come back. If they did
not, check they fit the flash (below).

## Retained values are behind by a few seconds

Working as intended. A value that keeps changing is saved at most once per
Persistent Storage's save period, so up to that much change before a power cut
or a crash is lost. Stopping the PLC cleanly, `RESTART` and a deep `SLEEP` save
everything first.

## Retained values never come back, whatever the setting

The retained variables may not fit the NVS flash (keep them under about 50 KB on
the ModBee Node UIO board, about 7 KB on a plain ESP32 target). Retain what a
restart cannot reconstruct rather than everything — a total, not the readings that make it up.

## `NETWORK` says connected but the credentials are ignored

Also working as intended. Something else brought the radio up first — Modbus
TCP in the firmware, or a protocol library — and this block joined what was
already there rather than fighting it. The credentials are only applied to a
radio that is down, or to one `NETWORK` brought up itself - a new SSID or
password on a radio it started does make it leave and join again.

## A flow total does not move

`PULSE_COUNT.STATUS` first. `UIO_TOO_LARGE`: four inputs are already counted
(the chip has four counters). `COUNTING` TRUE and `PULSES` still 0: the meter's
output is not reaching the input - check it on `DIGITAL_IN` with the meter
running. A reed (contact) meter that counts far too many: contact bounce,
which the hardware filter (about 12 µs) cannot remove; use an open-collector
meter or an RC filter.

## An expansion module reads `UIO_XS_NO_DRIVER`

It answers at its address, and this firmware cannot read that kind of chip
yet, so its channels are never trusted. See [08 I2C expansion](08-expansion.md).
`UIO_XS_MISSING`: nothing answers - run `UIO_I2C_SCAN` and compare the address
(most modules have address jumpers). `UIO_XS_IN_USE`: 16#49 and 16#5F are the
board's own converters, or two rows share an address.

## The board restarted by itself

`SYS_INFO.RESET_REASON`: `UIO_RST_PANIC` is a crash, the `_WDT` reasons a
task that hung (look at `STACK_MIN` / `STACK_TASK`), `UIO_RST_BROWNOUT` the
supply. `HEAP_MIN` falling day after day is a leak.

## Nothing works and `STATUS` says `UIO_UNSUPPORTED`

The program is running somewhere that is not the board — the simulator, or a
host build. Every call answers that off the target.

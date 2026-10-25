# 05 - Retained variables

## Declaring one

Mark the variable `RETAIN` in the variables table, or write it in ST:

```
PROGRAM main
  VAR RETAIN
    partsMade : UDINT;
    setpoint : INT := 500;
  END_VAR
END_PROGRAM
```

Then switch on **Persistent Storage** in the project's device settings. That is
all: `partsMade` now survives a power cut. There is no block to place and no pin
to wire.

`RETAIN` is inherited: declaring a function block instance `RETAIN` retains
everything inside it, and a member opts out with `NON_RETAIN`.

## Where they are kept

This library does not store anything itself. The Node UIO keeps its retained
values the way every ESP32 board does in OpenPLC: the firmware's built-in store
writes them to the board's NVS flash, in the namespace `oplc_retain`. The
runtime hands the values over, the store saves them, and the runtime puts them
back at start-up.

Persistent Storage off means nothing is stored: every retained variable starts
at its declared initial value on every start.

## What it costs, and why there is a delay

Nothing is written while nothing changes. A change after a quiet spell is saved
straight away. Changes that follow within the **save period** (Persistent
Storage's save period setting, in seconds) are held and saved together, latest
values only, when the period ends. So a setpoint change is kept at once, and a
value that keeps changing costs at most one write per period.

That is the trade to understand: **a value that keeps changing can lose up to
one save period of change in a power cut.** Shorten the period and you lose less
but spend flash life; lengthen it and the opposite. The default on an ESP32 is
60 seconds; ten suits most machines.

Stopping the PLC cleanly saves anything held, and so do `RESTART` and a deep
`SLEEP`: each saves the retained values just before the board goes down, and
waits for the save (about 10 to 50 ms). A power cut or a crash cannot. A light
sleep keeps RAM and leaves anything held until the board wakes.

## When the values do not come back

Two different things, worth telling apart.

**Editing your program keeps them.** Change a rung, add a variable that is not
retained, rename a POU — the retained values still come back.

**Changing a retained variable itself may not.** The runtime puts back each
retained variable it can still match to the program. One that was added, or
whose type changed, starts at its declared initial value. A stored copy that is
damaged is refused whole, and every retained variable starts at its initial
value.

That refusal is the point. Restoring bytes into variables they were not written
for would give a machine plausible-looking values that are wrong, which is worse
than starting clean.

## The size limit

The store is sized to the program's retained variables, and they are kept in
the board's NVS flash, which is 128 KB on the ModBee Node UIO board (shared
with the Wi-Fi settings and the analog calibration). A save writes the new copy
before it frees the old one, so keep the retained variables under about
**50 KB**. On a plain ESP32 target the NVS is 20 KB: keep them under about 7 KB.
The firmware also holds two copies of the packed values in RAM (the latest, and
what was last saved), so each retained byte costs about two more bytes of RAM.

A program that retains more than the flash can take still builds and runs, but
its saves fail and the values come back as they were at the last save that
worked. Retain what a restart genuinely cannot reconstruct rather than
everything.

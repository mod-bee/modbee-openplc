# F_IoForceSlot — IO force slot

One commissioning force slot (used by the IO maps).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `eAddressQuality` | `E_IoQ` |  | Ok, or why the address is wrong (NoModule, NoChannel) |
| in | `bForcingAllowed` | `BOOL` |  | forcing allowed now (outputs: system Off) |
| in | `bReleaseAllForces` | `BOOL` |  | release now and refuse new forces |
| in | `tNow` | `TIME` |  | TIME() of this scan |
| in | `tForceTime` | `TIME` |  | how long a force lasts (already limited by the caller) |
| in-out | `stForceSlot` | `ST_IoForce` |  | the force slot |
| out | *(result)* | `BOOL` |  | TRUE while it forces |

## How it works

One commissioning force slot: `bCmdForceNow` starts it (or starts its time again), `bCmdReleaseNow` or `bReleaseAllForces` ends it, it ends by itself after `tForceTime`, a wrong address (`eAddressQuality` not Ok) or no permit refuses / ends it. A command held on acts once. Returns TRUE while it forces.

## Example

Used by the IO maps; rarely needed in a project.

**Back to** [the index](../README.md).

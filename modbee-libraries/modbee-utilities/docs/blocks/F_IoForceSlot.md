# F_IoForceSlot — IO force slot

One commissioning force slot (used by the IO maps).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `eWhere` | `E_IoQ` |  | Ok, or why the address is wrong (NoModule, NoChannel) |
| in | `bPermit` | `BOOL` |  | forcing allowed now (outputs: system Off) |
| in | `bRelease` | `BOOL` |  | release now and refuse new forces |
| in | `tNow` | `TIME` |  | `TIME()` |
| in | `tForceTime` | `TIME` |  | how long a force lasts (already limited by the caller) |
| in-out | `stS` | `ST_IoForce` |  | The force slot |
| out | *(result)* | `BOOL` | | TRUE while it forces |

## How it works

One commissioning force slot: `bCmdForce` starts it (or starts its time again), `bCmdRelease` or `bRelease` ends it, it ends by itself after `tForceTime`, a wrong address (`eWhere` not Ok) or no permit refuses / ends it. A command held on acts once. Returns TRUE while it forces.

## Example

Used by the IO maps; rarely needed in a project.

**Back to** [the index](../README.md).

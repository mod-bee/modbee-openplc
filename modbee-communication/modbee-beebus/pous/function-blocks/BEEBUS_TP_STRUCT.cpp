(* A whole STRUCT as topics this node owns. One block, one topic per member.

NODE        which node. Unwired = the only one. The node block must be called
            first.
VALUE       the STRUCT, or an ARRAY of STRUCTs or of simple values. Every
            member becomes a topic; a nested STRUCT's members and an array's
            elements each become one too.
TOPIC_ID    the first member's id. Each member after it takes the next id, in
            declaration order: TOPIC_ID + 0, + 1, + 2 ... 1..32767.
PREFIX      put before every member's name, e.g. 'sts.'. Empty for none. Only
            needed when two STRUCTs on one node share member names - and for
            an ARRAY, which it names: 'alarms' gives alarms[1].set.delay ...
WRITABLE    peers may write the members (settings, commands). Taken on the
            first scan only. FALSE (default): read-only, as before.
PULSE       WRITABLE only: a BOOL member written TRUE goes back to FALSE
            this long after (a momentary command, e.g. T#500ms - longer than
            the slowest task that reads it). T#0s: kept as written.
SETTLE      WRITABLE only: a write that asks for a result (a BEEBUS_TP_BIND,
            or BEEBUS_TP_WRITE with WANT_RESULT) is answered after the
            program has run one scan with it, plus this long: the member is
            read back, and a block that refused the value and put the old
            one back answers CHANGED with the value it kept. T#0s: one scan.
            A momentary BOOL (PULSE) is answered once taken.

BOUND       every member is registered on the node.
COUNT       how many topics the STRUCT became.
WRITTEN     one scan, when peers' writes were taken into the STRUCT.
WRITTEN_COUNT  how many members that scan (held).
WRITTEN_NAME   the first of them (held), e.g. 'set.hiMm'.
WRITTEN_INDEX  its position, from 1, in declaration order (held).
WRITTEN_BY  the node that wrote it (held).
LOST        writes dropped, running total: a member written more than 4
            times between two scans keeps the 4 newest, as Sparkplug does.
ERROR       no such node, or the STRUCT was refused.
STATUS      why. BEEBUS_OK when fine.
            BEEBUS_QUEUED, BEEBUS_OK, BEEBUS_NOT_INITIALISED,
            BEEBUS_INVALID_ARGUMENT, BEEBUS_UNKNOWN_NODE,
            BEEBUS_DUPLICATE_NODE_ID, BEEBUS_NOT_MAPPED, BEEBUS_DUPLICATE,
            BEEBUS_QUEUE_FULL, BEEBUS_TIMEOUT, BEEBUS_NODE_LOST,
            BEEBUS_SUPERSEDED, BEEBUS_CANCELLED, BEEBUS_REFUSED,
            BEEBUS_TYPE_MISMATCH, BEEBUS_NOT_SUBSCRIBED, BEEBUS_BUFFER_FULL
LAST_ERROR  which member, and what is wrong with it.

---

THE STRUCT DECLARATION IS THE TOPIC LIST. Everything an HMI shows goes in one
STRUCT, and one block publishes all of it:

  TYPE PLANT_STS : STRUCT
    systemMode  : INT;
    levelPct    : REAL;
    pumpRunning : BOOL;
    banner      : STRING(64);
    pumpHours   : REAL;
  END_STRUCT END_TYPE

  sts( NODE := node, VALUE := STS, TOPIC_ID := 100 );

  name           id    type
  systemMode     100   INT
  levelPct       101   REAL
  pumpRunning    102   BOOL
  banner         103   STRING
  pumpHours      104   REAL

THE MEMBER NAME IS THE TOPIC NAME, spelled as declared. A nested STRUCT adds
its member's name and a dot (hmi.systemMode), and an array element its
position in brackets, counting from 1 (spareReal[1], spareReal[2] ...). Names
are 255 characters at most, PREFIX included - all the wire can say. A longer
one is not cut short - two names cut to the same 255 would become one topic
across the whole network - so the STRUCT is refused and LAST_ERROR names the
member. A node built with an older BeeBus (before names grew past 31) refuses a
longer name it is sent, and does not learn that topic: keep names to 31
characters while such a node is on the ring.

AN ARRAY ON VALUE is one block for a list of alike things - alarms, pumps,
zones. Each element's members become topics named PREFIX, the element's
position in brackets from 1, then the member's name; the variable's own name
is not part of it:

  TYPE ALARM : STRUCT
    active : BOOL;
    delay  : TIME;
  END_STRUCT END_TYPE

  ALM : ARRAY[1..8] OF ALARM;

  alm( NODE := node, VALUE := ALM, TOPIC_ID := 300, PREFIX := 'alarms',
       WRITABLE := TRUE );

  name               id
  alarms[1].active   300
  alarms[1].delay    301
  alarms[2].active   302
  ...
  alarms[8].delay    315

An ARRAY of simple values names its elements PREFIX[1], PREFIX[2] ...
The subscriber (BEEBUS_TP_STRUCT_SUBSCRIBE) wires an ARRAY of the same type
and gives the same PREFIX. WRITABLE works as for a STRUCT, and the whole ARRAY
is one block.

THE ID IS TOPIC_ID PLUS THE MEMBER'S POSITION, counting from 0, every array
element and nested member one position. Adding a member at the END keeps
every id; adding one in the middle moves the ones after it. Put new members
at the end, or leave a spare.

THE DECLARED TYPE IS THE TYPE ON THE WIRE:

  BOOL                                   bool
  SINT / USINT, BYTE                     8-bit
  INT / UINT, WORD                       16-bit
  DINT / UDINT, DWORD                    32-bit
  LINT / ULINT, LWORD                    64-bit
  REAL                                   32-bit float
  LREAL                                  64-bit float
  STRING(n)                              text
  TIME, TOD                              DINT milliseconds
  LTIME                                  LINT nanoseconds, as IEC 61131-3
                                         defines it
  DT, DATE                               UDINT seconds since 1970-01-01
  an enumeration                         its integer

WSTRING is refused: a value the wire cannot carry whole would be wrong rather
than missing.

There is no request pin. Once bound the node publishes each member on its
own, to every subscriber, on the deadband and interval each asked for. Move a
member and it goes out.

MEMBERS TRAVEL ONE BY ONE. Five members changed on one scan go out as five
values, a few to each turn of the token, so the far end may see them arrive
over two or three scans. Do not use one member as a "the rest has arrived"
flag; wait for the values themselves.

Peers may read these topics. With WRITABLE they may also write them, the way
Sparkplug WRITABLE works: a write never lands behind the program's back. The
node holds it in a queue and this block takes it in its own scan, one
write per member a scan, oldest first, so a command written 1 and then 0
between two scans is seen as both. The queue is sized from the program, when
the blocks bind: a waiting write for every WRITABLE member of the node at once
(at least 32), and a text for every WRITABLE STRING member (at least 4). Any
number of WRITABLE STRUCTs, on any number of nodes; every BOOL member can be a
momentary command (PULSE) at the same time. Check a written setting after WRITTEN and
put the old value back when it is refused: the change goes out to every
subscriber, so the writer sees its write bounce. Bind settings and commands
as their own WRITABLE STRUCT and status as a read-only one.

The instance binds once, on the first scan the node is there. Wire the same
variable every scan.

The whole table - names, ids, types - can be generated from the .st file that
declares the STRUCT, as Markdown and as JSON for an HMI's firmware. *)

FUNCTION_BLOCK BEEBUS_TP_STRUCT
  VAR_IN_OUT
    NODE : BEEBUS_NODE;
  END_VAR
  VAR_INPUT
    VALUE : ANY;
    TOPIC_ID : UINT;
    PREFIX : STRING(16);
    WRITABLE : BOOL;
    PULSE : TIME;
    SETTLE : TIME;
  END_VAR
  VAR_OUTPUT
    BOUND : BOOL;
    COUNT : UINT;
    ERROR : BOOL;
    STATUS : BEEBUS_RESULT;
    LAST_ERROR : STRING(80);
    WRITTEN : BOOL;
    WRITTEN_COUNT : UINT;
    WRITTEN_NAME : STRING(64);
    WRITTEN_INDEX : UINT;
    WRITTEN_BY : BYTE;
    LOST : UDINT;
  END_VAR
  VAR
    isBound : BOOL;
    fbPlan : __XWORD;
  END_VAR
#include <BeeBusAPI.h>

// Defined by the BEEBUS_NODE block, which every project has.
void* bb_planBuild(const strucpp::IEC_ANY& v, bool bits, char* err, size_t errCap);
uint32_t bb_planLeaves(void*);
bool bb_planMoved(void*, const strucpp::IEC_ANY& v);
bool bb_planBindTopicsEx(void*, BeeBusAPI* node, bool remote, uint8_t peer,
                         uint16_t topicId, const char* prefix, bool writable,
                         char* err, size_t errCap);
bool bb_planQueueWrites(void*, BeeBusAPI* node, char* err, size_t errCap);
uint32_t bb_planTakeWrites(void*, uint32_t pulseMs, uint32_t* firstLeaf, uint8_t* by,
                           uint32_t* lost);
bool bb_planLeafInfo(void*, uint32_t leaf, char* name, size_t cap, uint32_t* regOffset);
int32_t bb_millisOf(const strucpp::IEC_TIME& t);
void bb_planPublishSync(void*);
void bb_planServeTerms(void*, uint32_t settleMs, bool command);

strucpp::XWORD_t bb_currentTask();
bool bb_inTask(strucpp::XWORD_t owner);

void setup()
{
  BOUND = false;
  COUNT = 0;
  WRITTEN = false;
  WRITTEN_COUNT = 0;
  WRITTEN_NAME = "";
  WRITTEN_INDEX = 0;
  WRITTEN_BY = 0;
  LOST = 0;
  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;
  LAST_ERROR = "";
  isBound = false;
  fbPlan = (strucpp::XWORD_t)0;
}

void loop()
{
    if (!bb_inTask((strucpp::XWORD_t)NODE.FBTASK)) {   // one task per node: see BEEBUS_ARDUINO
        ERROR = true;
        STATUS = BEEBUS_RESULT::BEEBUS_WRONG_TASK;
        return;
    }
  BeeBusAPI* node = (BeeBusAPI*)(uintptr_t)(strucpp::XWORD_t)NODE.API;
  if (!node) {
    BOUND = false;
    ERROR = true;
    STATUS = BEEBUS_RESULT::BEEBUS_UNKNOWN_NODE;
    return;
  }

  // Bound once. A refusal is final until the PLC restarts, and LAST_ERROR
  // names the member: a name over 255 characters, a type BeeBus does not
  // carry, an id already taken.
  if (!(bool)isBound) {
    if ((bool)ERROR && STATUS == BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT) return;
    char why[96] = "";
    void* made = bb_planBuild(VALUE, false, why, sizeof(why));
    const bool writable = (bool)WRITABLE;
    if (!made || !bb_planBindTopicsEx(made, node, false, 0, (uint16_t)TOPIC_ID,
                                      PREFIX.c_str(), writable, why, sizeof(why)) ||
        (writable && !bb_planQueueWrites(made, node, why, sizeof(why)))) {
      BOUND = false;
      ERROR = true;
      STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
      LAST_ERROR = why;
      return;
    }
    fbPlan = (strucpp::XWORD_t)(uintptr_t)made;
    COUNT = (uint16_t)bb_planLeaves(made);
    isBound = true;
  }

  void* plan = (void*)(uintptr_t)(strucpp::XWORD_t)fbPlan;
  BOUND = true;

  if (bb_planMoved(plan, VALUE)) {
    ERROR = true;
    STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
    LAST_ERROR = "VALUE moved: wire the same variable every scan";
    return;
  }

  // Peers' writes waiting in the node's queue: one per member, oldest first,
  // into the variable before the copies below follow it.
  WRITTEN = false;
  uint32_t first = 0, lost = 0;
  uint8_t by = 0;
  const int32_t pulse = bb_millisOf(PULSE);
  const int32_t settle = bb_millisOf(SETTLE);
  bb_planServeTerms(plan, (uint32_t)(settle > 0 ? settle : 0), false);
  const uint32_t taken = bb_planTakeWrites(plan, (uint32_t)(pulse > 0 ? pulse : 0), &first, &by, &lost);
  if (lost > 0) LOST = (uint32_t)LOST + lost;
  if (taken > 0) {
    char name[64] = "";
    bb_planLeafInfo(plan, first, name, sizeof(name), nullptr);
    WRITTEN = true;
    WRITTEN_COUNT = (uint16_t)taken;
    WRITTEN_NAME = name;
    WRITTEN_INDEX = (uint16_t)(first + 1);
    WRITTEN_BY = by;
  }

  // The topics are bound to the members themselves; a TIME, a DT or a STRING
  // goes through a copy in its wire form, brought up to date here, so the node
  // publishes what the program holds as of this scan.
  bb_planPublishSync(plan);

  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;
  LAST_ERROR = "";
}

END_FUNCTION_BLOCK
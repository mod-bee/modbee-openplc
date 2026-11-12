(* Text-message commands: a message from an allowed number that says one of
COMMAND's words sets Q, and CMD says which - for whatever the program wires it
to: a pump start, an irrigation stop, a modem restart, a controller reboot.
One block for a whole list (or a list of one), beside the one GSM_SMS_RECEIVE
that reads the SIM.

INBOX         the GSM_SMS_RECEIVE. Call it first in the scan, then every
              GSM_SMS_COMMAND: they all look at the message it took this scan.
ENABLE        FALSE ignores every message (and counts nothing).
COMMAND       the commands, separated by commas: 'START, STOP, SET TIME'.
              Upper or lower case, extra spaces: all the same. The first one a
              message starts with is the one taken.
ALLOWED       who may send it: phone numbers separated by commas or
              semicolons, e.g. '+64 21 123 4567, 021 987 6543' (spaces inside a
              number are fine). Matched on their
              last 8 digits, so +64 21 ... and 021 ... are the same number.
              A sender that is a NAME or a short code (a provider's portal,
              e.g. 'PTT NZ' or '2001') is written as it arrives and matched
              whole, upper or lower case. Not sure what a portal sends as?
              Send a command: LAST_REFUSED shows it.
              A name is never answered (it cannot be texted back).
              Empty: nobody (the safe default). '*': anybody - only with a PIN.
PIN           the operator PIN for COMMAND. 0 or less: no PIN. Above 0: the
              message must start with it, e.g. '1111 START'.
ADMIN_COMMAND commands that need ADMIN_PIN, as COMMAND: 'REBOOT, RECONNECT'.
              Their CMD numbers follow COMMAND's (COMMAND has 8: the first
              admin command is CMD 9).
ADMIN_PIN     0 or less: no admin level - ADMIN_COMMAND is taken like COMMAND.
              Above 0: ADMIN_COMMAND needs it ('9999 REBOOT'); an operator PIN
              there is refused ('needs the admin PIN'). ADMIN_PIN works for
              COMMAND too.
PULSE         how long Q stays TRUE. T#0s: one scan.
REPLY         0 never answer; 1 answer an accepted command (the default:
              'OK REBOOT'); 2 also say why a message was refused. A refusal
              never answers a number that is not on ALLOWED. Use 0 with a SIM
              that cannot send texts (IoT plans that take them only from the
              provider's portal), or every answer shows as ERROR.
REPLY_TEXT    the answer instead of 'OK <command>', e.g. a status line the
              program builds. Empty: 'OK <command> <argument>'.
MAX_PER_HOUR  the most it acts in an hour; past it a message is refused. 0: no
              limit. A command that reboots or starts a pump wants a small one.

Q             TRUE for PULSE when an allowed message said one of COMMAND.
CMD           which one, from 1 in COMMAND's order (held until the next).
MATCHED       its words, as the block reads them: upper case, single spaces (held).
ARG           what followed the command, e.g. '1500' in 'SETLEVEL 1500'.
VALUE         ARG as a number; VALUE_OK when it was one.
DURATION      ARG as a time; DURATION_OK when it was one: number-and-unit
              pieces, D H M S MS, e.g. '3H30M10S', '90M', '1.5H', '2H 15M',
              'T#3h30m'. A bare number is not a time.
ADMIN         the last accepted command came with ADMIN_PIN.
SENT_BY       who sent the last accepted command.
COUNT         commands accepted since the PLC started.
REFUSED       messages that said one of COMMAND and were refused: not on ALLOWED, a
              wrong or missing PIN, or MAX_PER_HOUR reached.
LAST_REFUSED  why, and from whom.
ERROR         INBOX is not running (no modem), or a reply could not be sent.
STATUS        why. GSM_OK when fine.

---

  inbox( MODEM := modem );
  sms( INBOX := inbox, COMMAND := 'REBOOT, START, STOP', ALLOWED := numbers,
       PIN := pin, MAX_PER_HOUR := 5 );
  restart( REQ := sms.Q AND sms.CMD = 1 );
  run.cmdStart := sms.Q AND sms.CMD = 2;

ONLY ONE MESSAGE IS LOOKED AT EACH SCAN, the one GSM_SMS_RECEIVE took - so
call the receive block first and this one after it, in the same task. A
message that matches no command is ignored (and deleted from the SIM by
GSM_SMS_RECEIVE, as always). Several GSM_SMS_COMMANDs may share one
GSM_SMS_RECEIVE - for different numbers or PINs, say.

A REPLY IS ONE SMS AND COSTS ONE. The block keeps its reply until the modem
takes it; a command arriving meanwhile replaces it. A reply
waits for the network to accept the SIM (REGISTERED), not for data. *)

FUNCTION_BLOCK GSM_SMS_COMMAND
  VAR_INPUT
    ENABLE : BOOL := TRUE;
    COMMAND : STRING(160);
    ALLOWED : STRING(200);
    PIN : DINT;
    ADMIN_COMMAND : STRING(160);
    ADMIN_PIN : DINT;
    PULSE : TIME;
    REPLY : USINT := 1;
    REPLY_TEXT : STRING(140);
    MAX_PER_HOUR : UINT := 10;
  END_VAR
  VAR_OUTPUT
    Q : BOOL;
    CMD : INT;
    MATCHED : STRING(32);
    ARG : STRING(64);
    VALUE : REAL;
    VALUE_OK : BOOL;
    DURATION : TIME;
    DURATION_OK : BOOL;
    ADMIN : BOOL;
    SENT_BY : STRING(23);
    COUNT : UDINT;
    REFUSED : UDINT;
    LAST_REFUSED : STRING(64);
    ERROR : BOOL;
    STATUS : GSM_RESULT;
  END_VAR
  VAR_IN_OUT
    INBOX : GSM_SMS_RECEIVE;
  END_VAR
  VAR
    fbJob : __XWORD;
    fbQAt : UDINT;
    fbHourAt : UDINT;
    fbHourCount : UINT;
    fbStarted : BOOL;
    fbReplyTo : STRING(23);
    fbReplyText : STRING(160);
    fbReplyWanted : BOOL;
  END_VAR

#include <ModBeeGsmPlc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

namespace {

// Upper case, one space between words, none at either end.
void smsNormalise(const char* in, char* out, size_t cap)
{
    size_t n = 0;
    bool space = false;
    for (; *in != '\0' && n + 1 < cap; ++in) {
        char c = *in;
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            space = n > 0;
            continue;
        }
        if (space && n + 2 < cap) out[n++] = ' ';
        space = false;
        if (c >= 'a' && c <= 'z') c = (char)(c - 'a' + 'A');
        out[n++] = c;
    }
    out[n] = '\0';
}

// The last 8 digits of a number ('' when it has fewer than 6): +64 21 123 4567
// and 021 123 4567 are one number.
void smsTail(const char* number, char* out)
{
    char digits[32];
    size_t n = 0;
    for (; *number != '\0' && n + 1 < sizeof digits; ++number) {
        if (*number >= '0' && *number <= '9') digits[n++] = *number;
    }
    digits[n] = '\0';
    if (n < 6) {
        out[0] = '\0';
        return;
    }
    strcpy(out, n > 8 ? digits + (n - 8) : digits);
}

// Whether `sender` is on the list ('*' = anybody, empty = nobody). Entries are
// separated by commas or semicolons; spaces inside a number are part of it. A
// phone number matches on its last 8 digits; a name or short code (fewer than 6
// digits: 'PTT NZ', '2001') matches whole, upper or lower case.
bool smsAllowed(const char* list, const char* sender)
{
    char want[16];
    smsTail(sender, want);
    char wantWhole[32];
    smsNormalise(sender, wantWhole, sizeof wantWhole);
    if (want[0] == '\0' && wantWhole[0] == '\0') return false;
    char entry[32];
    size_t n = 0;
    for (const char* p = list;; ++p) {
        const char c = *p;
        if (c == ',' || c == ';' || c == '\n' || c == '\0') {
            entry[n] = '\0';
            char trimmed[32];
            smsNormalise(entry, trimmed, sizeof trimmed);
            if (strcmp(trimmed, "*") == 0) return true;
            if (n > 0) {
                char have[16];
                smsTail(entry, have);
                if (want[0] != '\0') {
                    if (have[0] != '\0' && strcmp(have, want) == 0) return true;
                } else if (have[0] == '\0' && strcmp(trimmed, wantWhole) == 0) {
                    return true;
                }
            }
            n = 0;
            if (c == '\0') return false;
            continue;
        }
        if (n + 1 < sizeof entry) entry[n++] = c;
    }
}

// Whether `text` starts with the PIN as its own word: the PIN's length, else 0.
size_t smsPinAt(const char* text, int32_t pin)
{
    if (pin <= 0) return 0;
    char p[16];
    snprintf(p, sizeof p, "%ld", (long)pin);
    const size_t pl = strlen(p);
    return strncmp(text, p, pl) == 0 && (text[pl] == ' ' || text[pl] == '\0') ? pl : 0;
}

// The first of a comma list's commands `rest` starts with (normalised, as a
// whole word): its position in the list from 1, its words in `out`; 0 none.
int smsFind(const char* list, const char* rest, char* out, size_t cap)
{
    char item[48];
    size_t n = 0;
    int index = 0;
    for (const char* q = list;; ++q) {
        if (*q == ',' || *q == ';' || *q == '\0') {
            item[n] = '\0';
            char word[40];
            smsNormalise(item, word, sizeof word);
            if (word[0] != '\0') {
                ++index;
                const size_t wl = strlen(word);
                if (strncmp(rest, word, wl) == 0 && (rest[wl] == ' ' || rest[wl] == '\0')) {
                    snprintf(out, cap, "%s", word);
                    return index;
                }
            }
            n = 0;
            if (*q == '\0') return 0;
            continue;
        }
        if (n + 1 < sizeof item) item[n++] = *q;
    }
}

// How many commands a comma list holds.
int smsCount(const char* list)
{
    char none[4];
    int count = 0;
    char item[48];
    size_t n = 0;
    for (const char* q = list;; ++q) {
        if (*q == ',' || *q == ';' || *q == '\0') {
            item[n] = '\0';
            smsNormalise(item, none, sizeof none);
            if (none[0] != '\0') ++count;
            n = 0;
            if (*q == '\0') return count;
            continue;
        }
        if (n + 1 < sizeof item) item[n++] = *q;
    }
}

// ARG as a time: number-and-unit pieces (D H M S MS, upper case as the text
// is), spaces between them allowed, an optional 'T#'. A bare number is not one.
bool smsDuration(const char* s, int64_t* ns)
{
    if (s[0] == 'T' && s[1] == '#') s += 2;
    double total = 0.0;
    int pieces = 0;
    while (*s != '\0') {
        if (*s == ' ' || *s == '_') { ++s; continue; }
        if (!((*s >= '0' && *s <= '9') || *s == '.')) return false;
        char* end = nullptr;
        const double v = strtod(s, &end);
        if (end == s || v < 0.0) return false;
        s = end;
        double unit;
        if (s[0] == 'M' && s[1] == 'S') { unit = 1e6; s += 2; }
        else if (*s == 'D') { unit = 86400e9; ++s; }
        else if (*s == 'H') { unit = 3600e9; ++s; }
        else if (*s == 'M') { unit = 60e9; ++s; }
        else if (*s == 'S') { unit = 1e9; ++s; }
        else return false;
        total += v * unit;
        ++pieces;
    }
    if (pieces == 0 || total > 9.2e18) return false;
    *ns = (int64_t)(total + 0.5);
    return true;
}

// Whether a sender can be texted back: a number, not a name ('PTT NZ' cannot).
bool smsCanAnswer(const char* sender)
{
    bool digit = false;
    for (; *sender != '\0'; ++sender) {
        const char c = *sender;
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) return false;
        if (c >= '0' && c <= '9') digit = true;
    }
    return digit;
}

} // namespace

void setup()
{
    Q = false;
    CMD = 0;
    VALUE_OK = false;
    DURATION_OK = false;
    ADMIN = false;
    COUNT = 0;
    REFUSED = 0;
    ERROR = false;
    STATUS = GSM_RESULT::GSM_OK;
    fbJob = 0;
    fbReplyWanted = false;
    fbStarted = false;
}

void loop()
{
    const uint32_t now = (uint32_t)gsm_millis();
    if (!(bool)fbStarted) {
        fbStarted = true;
        fbHourAt = now;
        fbHourCount = 0;
    }
    if (now - (uint32_t)fbHourAt >= 3600000u) {
        fbHourAt = now;
        fbHourCount = 0;
    }
    // Q: one scan, or PULSE long.
    if ((bool)Q && now - (uint32_t)fbQAt >= gsmplc::millisOf(PULSE.get())) Q = false;

    // --- this scan's message: first, every scan, never waiting for the modem. GSM_SMS_RECEIVE offers
    // a message for ONE scan; a block that returned early whenever COMMS_LINK held the modem missed it
    // (the Node, 2026-11-12: '9999 HAT POWER CYCLE' received, never taken). Only the reply needs the
    // modem, and it waits for it below.
    auto takeMessage = [&]() {
        if (!(bool)ENABLE || !(bool)INBOX.RECEIVED || (COMMAND.length() == 0 && ADMIN_COMMAND.length() == 0)) return;

        char text[200];
        smsNormalise(INBOX.TEXT.c_str(), text, sizeof text);

        // The PIN (admin or operator), then the command.
        const int32_t opPin = (int32_t)PIN;
        const int32_t adPin = (int32_t)ADMIN_PIN;
        const char* rest = text;
        bool pinOk = true;
        bool admin = false;
        size_t pl;
        if ((pl = smsPinAt(text, adPin)) > 0) {
            admin = true;
            rest = text + pl + (text[pl] == ' ' ? 1 : 0);
        } else if ((pl = smsPinAt(text, opPin)) > 0) {
            rest = text + pl + (text[pl] == ' ' ? 1 : 0);
        } else if (opPin > 0) {
            // A wrong or missing PIN still names the command after its first word.
            pinOk = false;
            const char* sp = strchr(text, ' ');
            rest = sp ? sp + 1 : text;
        }
        // The first of COMMAND's, then ADMIN_COMMAND's, the message starts with.
        char command[40] = "";
        int which = smsFind(COMMAND.c_str(), rest, command, sizeof command);
        bool adminCommand = false;
        if (which == 0 && !pinOk) {
            // No PIN at all: the whole text may be the command ('START').
            which = smsFind(COMMAND.c_str(), text, command, sizeof command);
            if (which != 0) rest = text;
        }
        if (which == 0 && ADMIN_COMMAND.length() > 0) {
            int a = smsFind(ADMIN_COMMAND.c_str(), rest, command, sizeof command);
            if (a == 0 && !pinOk) {
                a = smsFind(ADMIN_COMMAND.c_str(), text, command, sizeof command);
                if (a != 0) rest = text;
            }
            if (a != 0) {
                which = smsCount(COMMAND.c_str()) + a;
                adminCommand = true;
            }
        }
        if (which == 0) return;   // none of ours
        // An admin command needs ADMIN_PIN (when there is one); an operator PIN is refused.
        const bool levelOk = !adminCommand || adPin <= 0 || admin;
        const size_t cl = strlen(command);
        const char* arg = rest + cl + (rest[cl] == ' ' ? 1 : 0);

        const char* sender = INBOX.SENDER.c_str();
        const bool numberOk = smsAllowed(ALLOWED.c_str(), sender);
        const bool rateOk = (uint16_t)MAX_PER_HOUR == 0 || (uint16_t)fbHourCount < (uint16_t)MAX_PER_HOUR;

        if (!numberOk || !pinOk || !levelOk || !rateOk) {
            REFUSED = (uint32_t)REFUSED + 1u;
            const char* why = !numberOk ? "not an allowed number" : !pinOk ? "wrong PIN"
                            : !levelOk ? "needs the admin PIN" : "too many this hour";
            char line[64];
            snprintf(line, sizeof line, "%s: %s", why, sender);
            LAST_REFUSED = line;
            // Say why only to a number on the list: a stranger learns nothing.
            if ((uint8_t)REPLY >= 2 && numberOk && smsCanAnswer(sender)) {
                char reply[160];
                snprintf(reply, sizeof reply, "REFUSED %s: %s", command, why);
                fbReplyTo = sender;
                fbReplyText = reply;
                fbReplyWanted = true;
            }
            return;
        }

        fbHourCount = (uint16_t)fbHourCount + 1u;
        COUNT = (uint32_t)COUNT + 1u;
        SENT_BY = sender;
        CMD = (int16_t)which;
        MATCHED = command;
        ARG = arg;
        char* end = nullptr;
        const double value = strtod(arg, &end);
        VALUE_OK = *arg != '\0' && end != nullptr && *end == '\0';
        VALUE = VALUE_OK ? (float)value : 0.0f;
        int64_t ns = 0;
        DURATION_OK = *arg != '\0' && smsDuration(arg, &ns);
        DURATION = DURATION_OK ? ns : (int64_t)0;
        ADMIN = admin;
        Q = true;
        fbQAt = now;
        if ((uint8_t)REPLY >= 1 && smsCanAnswer(sender)) {   // a name cannot be answered
            char reply[160];
            if (REPLY_TEXT.length() > 0) snprintf(reply, sizeof reply, "%s", REPLY_TEXT.c_str());
            else if (*arg != '\0') snprintf(reply, sizeof reply, "OK %s %s", command, arg);
            else snprintf(reply, sizeof reply, "OK %s", command);
            fbReplyTo = sender;
            fbReplyText = reply;
            fbReplyWanted = true;
        }
        ERROR = false;
        STATUS = GSM_RESULT::GSM_OK;
    };
    takeMessage();

    // --- the modem: a reply owed, its state -----------------------------------------
    gsmplc::TryHold hold;
    if (!hold.owned()) return;

    if (!gsmplc::isOpen()) {
        ERROR = (bool)ENABLE;
        STATUS = GSM_RESULT::GSM_NOT_INITIALISED;
        return;
    }
    if ((GSM_RESULT)STATUS == GSM_RESULT::GSM_NOT_INITIALISED) {   // the modem is up now
        ERROR = false;
        STATUS = GSM_RESULT::GSM_OK;
    }

    // --- a reply still owed --------------------------------------------------
    gsmplc::Job* job = (gsmplc::Job*)(uintptr_t)(strucpp::XWORD_t)fbJob;
    if (job != nullptr && job->done) {
        job->done = false;
        ERROR = !job->result.isOk();
        STATUS = ERROR ? (GSM_RESULT)(int)job->result.status() : GSM_RESULT::GSM_OK;
    }
    if ((bool)fbReplyWanted && (job == nullptr || !job->busy)) {
        if (job == nullptr) {
            job = gsmplc::newJob();
            fbJob = (strucpp::XWORD_t)(uintptr_t)job;
        }
        if (job == nullptr) {
            fbReplyWanted = false;
            ERROR = true;
            STATUS = GSM_RESULT::GSM_NOT_INITIALISED;
        } else {
            const GsmResult sent = gsmplc::sendSms(*job, fbReplyTo.c_str(), fbReplyText.c_str());
            // Not taken yet (the SIM not accepted, the modem busy): asked again next scan.
            if (sent.status() == GsmStatus::Queued) fbReplyWanted = false;
        }
    }

}


END_FUNCTION_BLOCK
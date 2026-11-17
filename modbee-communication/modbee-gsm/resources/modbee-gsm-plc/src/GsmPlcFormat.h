// ModBee GSM for OpenPLC - the modem block's Format method.
//
// Licensed under the GNU Affero General Public License, Version 3, WITH
// ADDITIONAL TERMS - see the modbee-gsm LICENSE. Commercial use requires a
// separate licence.

#pragma once

// =============================================================================
// A TEXT MESSAGE FROM A TEMPLATE AND A STRUCT
// =============================================================================
//
// Included by the modem blocks only, in the program's own translation unit,
// where the runtime's types (IEC_ANY, TypeDesc) are declared: it reads the
// STRUCT through its descriptor, as FB_SparkplugNode.Record does. Inline, so
// the two blocks that include it share one copy. Same naming rule as
// ModBeeGsmPlc.h.
//
// {path}           the member's natural form: 12.4, 42, TRUE, the text, 1h30m
// {path:N}         a REAL or LREAL with N decimals; a STRING cut to N characters
// {path:hm}        a TIME as hours and minutes: '2h00m', '48m'
// {path|A|B|C}     an integer, BOOL or enumeration as the word it indexes, from 0
//
// A path is members by name, '.' between them, an array element by [n] from
// 1 whatever its bounds: {irr.left}, {pump[2].hours}. {} is anyData itself
// when it is not a STRUCT. A placeholder that names nothing is copied as it
// stands, so a mistake shows in the message. Everything else - $N already
// turned into a line break by the compiler, a '$' - passes through.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

namespace gsmplc {
namespace format {

struct Field {
    int cls = 0;
    const uint8_t* at = nullptr;
    uint32_t bytes = 0;     // the value's width
    uint32_t cap = 0;       // a STRING's declared length
    const strucpp::EnumDesc* names = nullptr;   // an {attribute 'to_string'} enumeration's names
};

// One path segment against a descriptor's members: name and optional [n].
inline bool member(const strucpp::TypeDesc* desc, const uint8_t* base, const char* seg,
                   size_t segLength, Field& out, const strucpp::TypeDesc** nested) {
    size_t nameLength = segLength;
    long index = 0;
    const char* open = (const char*)memchr(seg, '[', segLength);
    if (open != nullptr) {
        nameLength = (size_t)(open - seg);
        index = strtol(open + 1, nullptr, 10);
        if (index < 1) { return false; }
    }
    if (desc == nullptr) { return false; }
    for (uint16_t i = 0; i < desc->MEMBERCOUNT; i++) {
        const strucpp::MemberDesc& m = desc->MEMBERS[i];
        if (m.NAME == nullptr || strlen(m.NAME) != nameLength ||
            strncasecmp(m.NAME, seg, nameLength) != 0) {
            continue;
        }
        const uint8_t* at = base + m.BYTEOFFSET;
        if (m.TYPECLASS == strucpp::TYPE_ARRAY) {
            if (open == nullptr || (uint32_t)index > m.NUMELEMENTS) { return false; }
            at += (uint32_t)(index - 1) * m.STRIDE;
            out.cls = (int)m.BASETYPECLASS;
            out.bytes = m.ELEMBITSIZE / 8;
        } else {
            if (open != nullptr) { return false; }
            out.cls = (int)m.TYPECLASS;
            out.bytes = m.BITSIZE / 8;
        }
        out.at = at;
        out.cap = m.CAP;
        out.names = strucpp::member_enum_desc(m);
        *nested = m.NESTED;
        return true;
    }
    return false;
}

// The value a path names, or false.
inline bool resolve(const strucpp::IEC_ANY& any, const char* path, size_t length, Field& out) {
    if (!any.wired()) { return false; }
    if (length == 0) {
        if (any.TYPECLASS == strucpp::TYPE_USERDEF || any.TYPECLASS == strucpp::TYPE_ARRAY) {
            return false;   // {} is a single value
        }
        out.cls = (int)any.TYPECLASS;
        out.at = any.PVALUE;
        out.bytes = (uint32_t)any.DISIZE;
        out.cap = (uint32_t)any.DISIZE;
        out.names = strucpp::any_enum_desc(any);
        return true;
    }
    // A path walks a STRUCT; only a STRUCT's descriptor lists members.
    if (any.TYPECLASS != strucpp::TYPE_USERDEF) { return false; }
    const strucpp::TypeDesc* desc = any.TYPEDESC;
    const uint8_t* base = any.PVALUE;
    const char* p = path;
    const char* end = path + length;
    while (p < end) {
        const char* dot = (const char*)memchr(p, '.', (size_t)(end - p));
        const char* segEnd = dot != nullptr ? dot : end;
        const strucpp::TypeDesc* nested = nullptr;
        if (!member(desc, base, p, (size_t)(segEnd - p), out, &nested)) { return false; }
        if (dot == nullptr) {
            return out.cls != (int)strucpp::TYPE_USERDEF;
        }
        if (out.cls != (int)strucpp::TYPE_USERDEF) { return false; }
        desc = nested;
        base = out.at;
        p = dot + 1;
    }
    return false;
}

// An integer of any class, for words and enumerations.
inline bool integerOf(const Field& f, int64_t* value) {
    switch (f.cls) {
    case strucpp::TYPE_BOOL: *value = *(const uint8_t*)f.at ? 1 : 0; return true;
    case strucpp::TYPE_SINT: *value = *(const int8_t*)f.at; return true;
    case strucpp::TYPE_INT: *value = *(const int16_t*)f.at; return true;
    case strucpp::TYPE_DINT: *value = *(const int32_t*)f.at; return true;
    case strucpp::TYPE_LINT: *value = *(const int64_t*)f.at; return true;
    case strucpp::TYPE_USINT: case strucpp::TYPE_BYTE: *value = *(const uint8_t*)f.at; return true;
    case strucpp::TYPE_UINT: case strucpp::TYPE_WORD: *value = *(const uint16_t*)f.at; return true;
    case strucpp::TYPE_UDINT: case strucpp::TYPE_DWORD: *value = *(const uint32_t*)f.at; return true;
    case strucpp::TYPE_ULINT: case strucpp::TYPE_LWORD: *value = (int64_t)*(const uint64_t*)f.at; return true;
    case strucpp::TYPE_ENUM:
        if (f.bytes == 1) { *value = *(const int8_t*)f.at; return true; }
        if (f.bytes == 4) { *value = *(const int32_t*)f.at; return true; }
        if (f.bytes == 8) { *value = *(const int64_t*)f.at; return true; }
        *value = *(const int16_t*)f.at;
        return true;
    default: return false;
    }
}

// Milliseconds as '1h30m', '45s', '1m30s', '250ms', '0s'.
inline void naturalTime(int64_t ms, char* out, size_t capacity) {
    size_t n = 0;
    out[0] = '\0';
    if (ms < 0) {
        n += (size_t)snprintf(out, capacity, "-");
        ms = -ms;
    }
    const int64_t parts[] = {86400000LL, 3600000LL, 60000LL, 1000LL, 1LL};
    const char* const units[] = {"d", "h", "m", "s", "ms"};
    bool any = false;
    for (int i = 0; i < 5 && n < capacity; i++) {
        const int64_t v = ms / parts[i];
        ms %= parts[i];
        if (v == 0) { continue; }
        n += (size_t)snprintf(out + n, capacity - n, "%lld%s", (long long)v, units[i]);
        any = true;
    }
    if (!any && n < capacity) { snprintf(out + n, capacity - n, "0s"); }
}

// Seconds since 1970 as a calendar date and time.
inline void civil(int64_t seconds, int64_t* y, int* mo, int* d, int* h, int* mi, int* s) {
    int64_t days = seconds / 86400;
    int64_t rest = seconds % 86400;
    if (rest < 0) { rest += 86400; days--; }
    *h = (int)(rest / 3600);
    *mi = (int)(rest % 3600 / 60);
    *s = (int)(rest % 60);
    // Howard Hinnant's civil_from_days.
    days += 719468;
    const int64_t era = (days >= 0 ? days : days - 146096) / 146097;
    const int64_t doe = days - era * 146097;
    const int64_t yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    const int64_t doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    const int64_t mp = (5 * doy + 2) / 153;
    *d = (int)(doy - (153 * mp + 2) / 5 + 1);
    *mo = (int)(mp < 10 ? mp + 3 : mp - 9);
    *y = yoe + era * 400 + (*mo <= 2 ? 1 : 0);
}

// One placeholder's text. False when its spec does not fit the value.
inline bool render(const Field& f, const char* spec, size_t specLength, char words,
                   char* out, size_t capacity) {
    out[0] = '\0';
    // {x|A|B|C}: the word at the value, from 0.
    if (words == '|') {
        int64_t value = 0;
        if (!integerOf(f, &value)) { return false; }
        const char* p = spec;
        const char* end = spec + specLength;
        for (int64_t i = 0; p <= end; i++) {
            const char* bar = (const char*)memchr(p, '|', (size_t)(end - p));
            const char* wordEnd = bar != nullptr ? bar : end;
            if (i == value) {
                const size_t n = (size_t)(wordEnd - p) < capacity - 1 ? (size_t)(wordEnd - p) : capacity - 1;
                memcpy(out, p, n);
                out[n] = '\0';
                return true;
            }
            if (bar == nullptr) { break; }
            p = bar + 1;
        }
        snprintf(out, capacity, "%lld", (long long)value);   // past the list: the number
        return true;
    }
    char specText[8] = {0};
    if (specLength >= sizeof specText) { return false; }
    memcpy(specText, spec, specLength);
    const bool hasSpec = specLength > 0;
    const bool hm = hasSpec && strcasecmp(specText, "hm") == 0;
    long digits = -1;
    if (hasSpec && !hm) {
        char* stop = nullptr;
        digits = strtol(specText, &stop, 10);
        if (stop == specText || *stop != '\0' || digits < 0 || digits > 160) { return false; }
    }

    switch (f.cls) {
    case strucpp::TYPE_REAL:
    case strucpp::TYPE_LREAL: {
        if (hm) { return false; }
        const double v = f.cls == strucpp::TYPE_REAL ? (double)*(const float*)f.at : *(const double*)f.at;
        if (digits >= 0) {
            snprintf(out, capacity, "%.*f", (int)(digits > 9 ? 9 : digits), v);
        } else {
            snprintf(out, capacity, f.cls == strucpp::TYPE_REAL ? "%.7g" : "%.15g", v);
        }
        return true;
    }
    case strucpp::TYPE_STRING: {
        if (hm) { return false; }
        const char* text = (const char*)f.at;
        size_t n = 0;
        const size_t bound = f.cap > 0 ? f.cap : 254;
        while (n < bound && text[n] != '\0') n++;
        if (digits >= 0 && (size_t)digits < n) { n = (size_t)digits; }
        if (n > capacity - 1) { n = capacity - 1; }
        memcpy(out, text, n);
        out[n] = '\0';
        return true;
    }
    case strucpp::TYPE_TIME:
    case strucpp::TYPE_LTIME: {
        if (digits >= 0) { return false; }
        const int64_t ms = *(const int64_t*)f.at / 1000000LL;
        if (hm) {
            const int64_t minutes = ms / 60000;
            if (minutes >= 60) {
                snprintf(out, capacity, "%lldh%02lldm", (long long)(minutes / 60), (long long)(minutes % 60));
            } else {
                snprintf(out, capacity, "%lldm", (long long)minutes);
            }
        } else {
            naturalTime(ms, out, capacity);
        }
        return true;
    }
    case strucpp::TYPE_DATEANDTIME:
    case strucpp::TYPE_DATE:
    case strucpp::TYPE_TIMEOFDAY: {
        if (hasSpec) { return false; }
        const int64_t seconds = *(const int64_t*)f.at / 1000000000LL;
        int64_t y; int mo, d, h, mi, s;
        civil(seconds, &y, &mo, &d, &h, &mi, &s);
        if (f.cls == strucpp::TYPE_DATE) {
            snprintf(out, capacity, "%04lld-%02d-%02d", (long long)y, mo, d);
        } else if (f.cls == strucpp::TYPE_TIMEOFDAY) {
            snprintf(out, capacity, "%02d:%02d:%02d", h, mi, s);
        } else {
            snprintf(out, capacity, "%04lld-%02d-%02d %02d:%02d:%02d", (long long)y, mo, d, h, mi, s);
        }
        return true;
    }
    case strucpp::TYPE_BOOL:
        if (hasSpec) { return false; }
        snprintf(out, capacity, "%s", *(const uint8_t*)f.at ? "TRUE" : "FALSE");
        return true;
    default: {
        // Integers: the number. An enumeration declared {attribute 'to_string'}:
        // its member's name, as TO_STRING gives it; any other enumeration (or
        // a value no member has): the number. {x|A|B|C} names them in the template.
        int64_t value = 0;
        if (hasSpec || !integerOf(f, &value)) { return false; }
        if (f.cls == strucpp::TYPE_ENUM) {
            const char* name = strucpp::enum_value_name(f.names, value);
            if (name != nullptr) {
                snprintf(out, capacity, "%s", name);
                return true;
            }
        }
        if (f.cls == strucpp::TYPE_ULINT || f.cls == strucpp::TYPE_LWORD) {
            snprintf(out, capacity, "%llu", (unsigned long long)*(const uint64_t*)f.at);
        } else {
            snprintf(out, capacity, "%lld", (long long)value);
        }
        return true;
    }
    }
}

// The template filled from `any`, at most `limit` characters; *cut when more
// would have followed.
inline void fill(const char* tmpl, const strucpp::IEC_ANY& any, char* out, size_t limit, bool* cut) {
    size_t n = 0;
    *cut = false;
    auto put = [&](const char* text, size_t length) {
        for (size_t i = 0; i < length; i++) {
            if (n >= limit) { *cut = true; return; }
            out[n++] = text[i];
        }
    };
    const char* p = tmpl != nullptr ? tmpl : "";
    while (*p != '\0' && !*cut) {
        if (*p != '{') {
            put(p, 1);
            ++p;
            continue;
        }
        const char* close = strchr(p, '}');
        if (close == nullptr) {
            put(p, strlen(p));
            break;
        }
        // {path[:spec | |words]}
        const char* inner = p + 1;
        const char* stop = inner;
        while (stop < close && *stop != ':' && *stop != '|') stop++;
        Field field;
        char text[176];
        const bool known = resolve(any, inner, (size_t)(stop - inner), field) &&
                           render(field, stop < close ? stop + 1 : close,
                                  stop < close ? (size_t)(close - stop - 1) : 0,
                                  stop < close ? *stop : '\0', text, sizeof text);
        if (known) {
            put(text, strlen(text));
        } else {
            put(p, (size_t)(close - p + 1));   // as it stands: the mistake shows
        }
        p = close + 1;
    }
    out[n] = '\0';
}

} // namespace format
} // namespace gsmplc

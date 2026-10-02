#!/usr/bin/env bash
# shellcheck disable=SC2034  # ev, fam and c are read inside check's eval strings
# Tests for clave-pim (APP-8): calendars and events (repeats, one repeat
# removed, all-day, moving between calendars), an imported .ics file as other
# apps export them (time zones, RRULE, EXDATE, an overridden repeat), and
# errors as one line, never a traceback. Scratch XDG_DATA_HOME. Needs
# python-icalendar and python-dateutil; PYTHON picks the interpreter (for a venv).
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
ok()   { echo "ok:   $*"; }
check() { if eval "$1"; then ok "$2"; else fail "$2"; fi; }
export XDG_DATA_HOME="$tmp/data" TZ=Europe/Madrid
pim() { "${PYTHON:-python3}" "$repo/home/.local/bin/clave-pim" "$@"; }

if ! "${PYTHON:-python3}" -c 'import icalendar, dateutil' 2>/dev/null; then
    echo "skip: python-icalendar or python-dateutil not installed"; exit 0
fi

# --- calendars and events ----------------------------------------------
check '[ "$(pim calendars | jq -r ".[0].id")" = Calendar ]' "a first calendar is made"
pim calendar-new Work '#ff9f0a' >/dev/null
check '[ "$(pim calendars | jq length)" = 2 ]' "a second calendar"
if pim calendar-new ../../evil 2>/dev/null; then :; fi
check '[ ! -e "$tmp/evil.ics" ] && [ ! -e "$XDG_DATA_HOME/evil.ics" ]' "a calendar name cannot leave the folder"

uid=$(echo '{"calendar":"Work","title":"Standup","start":"2026-10-05T09:30","end":"2026-10-05T09:45","repeat":"weekly"}' \
    | pim event-save | jq -r .uid)
ev=$(pim events 2026-10-01 2026-11-01)
check '[ "$(echo "$ev" | jq "[.[] | select(.uid == \"$uid\")] | length")" = 4 ]' "weekly event repeats 4 times in October"
check '[ "$(echo "$ev" | jq -r ".[0].start")" = 2026-10-05T09:30:00 ]' "local time kept"
check 'grep -q "TZID=\|DTSTART:.*Z\|DTSTART;" "$XDG_DATA_HOME/clave/calendars/Work.ics"' "start written with a zone"
# Moving the third repeat by an hour moves the series by an hour, from its own start.
echo "{\"calendar\":\"Work\",\"uid\":\"$uid\",\"occurrence\":\"2026-10-19T09:30:00\",\"title\":\"Standup\",\"start\":\"2026-10-19T10:30\",\"end\":\"2026-10-19T10:45\",\"repeat\":\"weekly\"}" | pim event-save >/dev/null
check '[ "$(pim events 2026-10-01 2026-11-01 | jq -r "[.[] | select(.uid == \"$uid\")] | .[0].start")" = 2026-10-05T10:30:00 ]' "editing a later repeat keeps the series start date"
echo "{\"calendar\":\"Work\",\"uid\":\"$uid\",\"occurrence\":\"2026-10-05T10:30:00\",\"title\":\"Standup\",\"start\":\"2026-10-05T09:30\",\"end\":\"2026-10-05T09:45\",\"repeat\":\"weekly\"}" | pim event-save >/dev/null
pim event-delete Work "$uid" 2026-10-12T09:30
check '[ "$(pim events 2026-10-01 2026-11-01 | jq "[.[] | select(.uid == \"$uid\")] | length")" = 3 ]' "one repeat removed (EXDATE)"

echo '{"calendar":"Calendar","title":"Holiday","start":"2026-10-12","end":"2026-10-13","allDay":true}' | pim event-save >/dev/null
check '[ "$(pim events 2026-10-12 2026-10-13 | jq -r ".[] | select(.title==\"Holiday\") | .allDay")" = true ]' "all-day event"
check 'grep -q "DTSTART;VALUE=DATE:20261012" "$XDG_DATA_HOME/clave/calendars/Calendar.ics"' "all-day written as a date"

echo "{\"calendar\":\"Calendar\",\"oldCalendar\":\"Work\",\"uid\":\"$uid\",\"title\":\"Standup\",\"start\":\"2026-10-05T10:00\",\"end\":\"2026-10-05T10:15\"}" | pim event-save >/dev/null
ev=$(pim events 2026-10-01 2026-11-01)
check '[ "$(echo "$ev" | jq -r "[.[] | select(.uid == \"$uid\")] | .[0].calendar")" = Calendar ]' "event moved to another calendar"
check '[ "$(echo "$ev" | jq "[.[] | select(.uid == \"$uid\")] | length")" = 1 ]' "repeat removed when the event is saved without it"
check '! grep -q "$uid" "$XDG_DATA_HOME/clave/calendars/Work.ics"' "gone from the old calendar"
pim event-delete Calendar "$uid"
check '[ "$(pim events 2026-10-01 2026-11-01 | jq "[.[] | select(.uid == \"$uid\")] | length")" = 0 ]' "event deleted"

# An export from another calendar app.
cat > "$tmp/export.ics" <<'EOF'
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Example Corp//Calendar 1.0//EN
X-WR-CALNAME:Family
BEGIN:VTIMEZONE
TZID:America/New_York
BEGIN:STANDARD
DTSTART:19701101T020000
RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU
TZOFFSETFROM:-0400
TZOFFSETTO:-0500
END:STANDARD
BEGIN:DAYLIGHT
DTSTART:19700308T020000
RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU
TZOFFSETFROM:-0500
TZOFFSETTO:-0400
END:DAYLIGHT
END:VTIMEZONE
BEGIN:VEVENT
UID:dinner-1@example.com
DTSTAMP:20260901T120000Z
DTSTART;TZID=America/New_York:20261002T190000
DTEND;TZID=America/New_York:20261002T210000
RRULE:FREQ=WEEKLY;COUNT=4
EXDATE;TZID=America/New_York:20261009T190000
SUMMARY:Family dinner
LOCATION:Home
END:VEVENT
BEGIN:VEVENT
UID:dinner-1@example.com
DTSTAMP:20260901T120000Z
RECURRENCE-ID;TZID=America/New_York:20261016T190000
DTSTART;TZID=America/New_York:20261016T200000
DTEND;TZID=America/New_York:20261016T220000
SUMMARY:Family dinner (late)
END:VEVENT
END:VCALENDAR
EOF
pim import "$tmp/export.ics" >/dev/null
check '[ "$(pim calendars | jq -r ".[] | select(.id==\"export\") | .name")" = Family ]' "imported calendar keeps its name"
fam=$(pim events 2026-10-01 2026-11-01 | jq '[.[] | select(.calendar=="export")]')
check '[ "$(echo "$fam" | jq length)" = 3 ]' "4 repeats minus 1 EXDATE, with 1 overridden = 3 events"
check '[ "$(echo "$fam" | jq -r ".[0].start")" = 2026-10-03T01:00:00 ]' "New York 19:00 shown at Madrid 01:00"
check '[ "$(echo "$fam" | jq -r "[.[] | select(.title==\"Family dinner (late)\")] | length")" = 1 ]' "overridden repeat shown once, changed"
if pim import "$tmp/nothing.txt" 2>/dev/null; then fail "non-calendar file refused"; else ok "non-calendar file refused"; fi

# --- errors: one line the app can show, never a Python traceback -----------
: > "$tmp/empty.ics"
echo "not a calendar" > "$tmp/junk.ics"
for f in empty junk; do
    err=$(pim import "$tmp/$f.ics" 2>&1 >/dev/null || true)
    check '[ -n "$err" ] && ! grep -q Traceback <<<"$err" && [ "$(wc -l <<<"$err")" = 1 ]' "unreadable $f.ics: one-line error"
done
err=$(echo '{bad' | pim event-save 2>&1 >/dev/null || true)
check '! grep -q Traceback <<<"$err" && grep -q JSON <<<"$err"' "bad event data: one-line error"
err=$(echo '{"calendar":"Calendar"}' | pim event-save 2>&1 >/dev/null || true)
check '! grep -q Traceback <<<"$err" && grep -q start <<<"$err"' "missing field: one-line error"
err=$(pim event-delete Nothing x 2>&1 >/dev/null || true)
check '! grep -q Traceback <<<"$err" && [ -n "$err" ]' "unknown calendar: one-line error"

echo
if [ "$fails" -eq 0 ]; then echo "All calendar tests passed."; else echo "$fails failed."; exit 1; fi

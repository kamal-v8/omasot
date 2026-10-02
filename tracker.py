#!/usr/bin/env python3
import fcntl
import json
import os
import datetime
import subprocess
import sys

STATE_FILE = os.path.expanduser("~/.local/state/screentime.json")
LOCK_FILE = STATE_FILE + ".lock"

SAMPLE_SECONDS = 5

TERMINAL_CLASSES = {
    "foot",
    "kitty",
    "alacritty",
    "ghostty",
    "wezterm",
    "konsole",
    "gnome-terminal",
    "xterm",
    "xfce4-terminal",
}

MONTH_ABBR = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]

APP_MODES = ("off", "class", "smart")

# Suffixes stripped when normalizing stored app names for display.
APP_NAME_SUFFIXES = (
    "-origin", "-default", "-launcher", "-bin", ".bin",
    "-stable", "-beta", "-dev", "-helper",
)

# Tokens that carry no app identity on their own; names collapsing to
# one of these are dropped and their seconds fold into unattributed.
APP_NAME_FRAGMENTS = {
    "com", "org", "net", "io", "app", "bin", "default", "unknown",
    "null", "none", "undefined", "(null)",
}


def clean_app_name(name):
    """Normalize a stored app key for display, or None if it is junk.

    Merge-only: stored keys are never rewritten, so history needs no
    migration and nothing is lost — dropped seconds surface as
    unattributed time instead.
    """
    try:
        if not isinstance(name, str):
            return None
        t = name.strip().lower()
        for _ in range(2):
            for suf in APP_NAME_SUFFIXES:
                if t.endswith(suf) and len(t) > len(suf) + 1:
                    t = t[: -len(suf)]
                    break
        t = t.strip("-_. ")
        if not t or t in APP_NAME_FRAGMENTS:
            return None
        if not any(c.isalnum() for c in t):
            return None
        return t
    except Exception:
        return None


def collect_app_items(apps_dict, limit, icon_cache=None):
    """Merge raw {name: seconds} into sorted display items.

    Returns (items, merged_total). Junk names (clean_app_name -> None)
    are skipped here; their seconds are accounted as unattributed by
    the caller via day totals.
    """
    if icon_cache is None:
        icon_cache = {}
    merged = {}
    try:
        entries = apps_dict.items()
    except Exception:
        entries = []
    for k, v in entries:
        if not (isinstance(k, str) and isinstance(v, int)):
            continue
        ck = clean_app_name(k)
        if ck is None:
            continue
        merged[ck] = merged.get(ck, 0) + v
    items = []
    for name, seconds in merged.items():
        if name not in icon_cache:
            try:
                icon_cache[name] = resolve_app_icon(name)
            except Exception:
                icon_cache[name] = ""
        items.append({"name": name, "seconds": seconds, "icon": icon_cache[name]})
    items.sort(key=lambda x: x["seconds"], reverse=True)
    total = sum(x["seconds"] for x in items)
    return items[:limit], total


def day_seconds(day):
    """Screen-on seconds for a day dict (hourly minutes × 60)."""
    try:
        if not isinstance(day, dict):
            return 0
        return sum(v for v in day.values() if isinstance(v, int)) * 60
    except Exception:
        return 0

_DESKTOP_ENTRY_CACHE = None


def _parse_desktop_file(path):
    """Parse StartupWMClass/Name/Exec/Icon from a .desktop file.

    Manual line parse (no configparser): never raises on malformed
    files, ignores localized keys (Name[xx]) and non-entry sections.
    Returns (wmclass, name, exec_base, icon) lowercased except icon.
    """
    wmclass = ""
    name = ""
    execv = ""
    icon = ""
    nodisplay = False
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            in_entry = True  # headerless files still parse
            for raw in f:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("["):
                    try:
                        sec = line[1:line.index("]")].strip()
                    except ValueError:
                        in_entry = False
                        continue
                    in_entry = (sec == "Desktop Entry")
                    continue
                if not in_entry:
                    continue
                if "=" not in line:
                    continue
                key, _, value = line.partition("=")
                key = key.strip()
                value = value.strip()
                if key == "StartupWMClass" and not wmclass:
                    wmclass = value
                elif key == "Name" and not name:
                    name = value
                elif key == "Exec" and not execv:
                    execv = value
                elif key == "Icon" and not icon:
                    icon = value
                elif key == "NoDisplay" and value.strip().lower() == "true":
                    nodisplay = True
    except Exception:
        return None
    try:
        exec_base = _exec_basename(execv)
    except Exception:
        exec_base = ""
    try:
        return {
            "wmclass": wmclass.strip().lower(),
            "name": name.strip().lower(),
            "exec": exec_base,
            "icon": icon.strip(),
            "nodisplay": nodisplay,
        }
    except Exception:
        return None


def _exec_basename(exec_value):
    try:
        s = (exec_value or "").strip()
        if not s:
            return ""
        if s[0] in ("'", '"'):
            q = s[0]
            end = s.find(q, 1)
            token = s[1:end] if end != -1 else s[1:]
        else:
            token = s.split(None, 1)[0]
        token = token.strip().strip("'\"").strip()
        if not token:
            return ""
        return os.path.basename(token).lower()
    except Exception:
        return ""


def _load_desktop_entries():
    """Scan .desktop files once per process; always returns a list."""
    global _DESKTOP_ENTRY_CACHE
    if _DESKTOP_ENTRY_CACHE is not None:
        return _DESKTOP_ENTRY_CACHE
    entries = []
    try:
        dirs = [
            "/usr/share/applications",
            os.path.expanduser("~/.local/share/applications"),
        ]
        for d in dirs:
            try:
                files = os.listdir(d)
            except Exception:
                continue
            for fn in files:
                if not fn.endswith(".desktop"):
                    continue
                try:
                    parsed = _parse_desktop_file(os.path.join(d, fn))
                except Exception:
                    continue
                if parsed is None:
                    continue
                # Background services (agents, auth daemons, helpers)
                # reuse generic names — never borrow their icons.
                if parsed.get("nodisplay"):
                    continue
                entries.append(parsed)
    except Exception:
        pass
    _DESKTOP_ENTRY_CACHE = entries
    return entries


def resolve_app_icon(app_name):
    """Return the desktop Icon= name for app_name, or "".

    Matches app_name against lowercased StartupWMClass, then Name,
    then Exec basename. Total-failure-safe: any exception -> "".
    """
    try:
        if not isinstance(app_name, str):
            return ""
        key = app_name.strip().lower()
        if not key:
            return ""
        if "." in key:
            key = key.split(".")[-1].strip()
            if not key:
                return ""
        entries = _load_desktop_entries()
        for field in ("wmclass", "name", "exec"):
            for e in entries:
                try:
                    if e.get(field) == key and e.get("icon"):
                        return e["icon"]
                except Exception:
                    continue
        return ""
    except Exception:
        return ""


def load_data():
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE, "r") as f:
            try:
                return json.load(f)
            except (json.JSONDecodeError, ValueError):
                pass
    return {}


def _is_date_key(key):
    if not isinstance(key, str):
        return False
    if len(key) != 10:
        return False
    if key[4] != "-" or key[7] != "-":
        return False
    try:
        datetime.datetime.strptime(key, "%Y-%m-%d")
        return True
    except (ValueError, TypeError):
        return False


def _get_retention_days(data):
    try:
        settings = data.get("_settings", {})
        if not isinstance(settings, dict):
            return 365
        retention = settings.get("retention_days", 365)
        retention = int(retention)
    except (ValueError, TypeError, AttributeError):
        return 365
    if retention < 1:
        retention = 1
    if retention > 365:
        retention = 365
    return retention


def prune_data(data):
    """Keep newest retention_days date keys; always keep underscore keys."""
    retention = _get_retention_days(data)
    date_keys = sorted(
        [k for k in data.keys() if _is_date_key(k)], reverse=True
    )
    keep = set(date_keys[:retention])
    pruned = {}
    for k, v in data.items():
        if isinstance(k, str) and k.startswith("_"):
            pruned[k] = v
        elif _is_date_key(k):
            if k in keep:
                pruned[k] = v
        else:
            # Unknown non-date, non-underscore key: keep to avoid data loss.
            pruned[k] = v
    return pruned


def save_data(data):
    data = prune_data(data)
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    tmp_file = STATE_FILE + ".tmp"
    with open(tmp_file, "w") as f:
        json.dump(data, f)
    os.replace(tmp_file, STATE_FILE)


def update_state(fn):
    """Load, mutate via fn(data), and save under an exclusive lock.

    The 60s day recorder and the 5s app recorder run as separate
    processes; without this lock their read-modify-write cycles
    interleave and the slower writer silently discards the faster
    one's increments (last-writer-wins on a stale read).
    """
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(LOCK_FILE, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            data = load_data()
            fn(data)
            save_data(data)
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def _normalize_app_name(value):
    if not isinstance(value, str):
        return None
    t = value.strip().lower()
    if not t:
        return None
    if "." in t:
        t = t.split(".")[-1].strip()
        if not t:
            return None
    return t


def _normalize_title(value):
    if not isinstance(value, str):
        return None
    t = value.strip().lower()
    if not t:
        return None
    return t


def _children_of(ppid):
    try:
        r = subprocess.run(
            ["ps", "-o", "pid=,comm=", "--ppid", str(ppid)],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if r.returncode != 0:
            return []
        out = []
        for line in r.stdout.splitlines():
            line = line.strip()
            if not line:
                continue
            parts = line.split(None, 1)
            if len(parts) != 2:
                continue
            try:
                cpid = int(parts[0])
            except (ValueError, TypeError):
                continue
            ccomm = parts[1].strip()
            if not ccomm:
                continue
            out.append((cpid, ccomm))
        return out
    except Exception:
        return []


def _deepest_leaf_comm(root_pid):
    try:
        root = int(root_pid)
    except (ValueError, TypeError):
        return None
    if root <= 0:
        return None

    best = None  # (depth, comm)

    def dfs(pid, depth):
        nonlocal best
        try:
            kids = _children_of(pid)
        except Exception:
            return None
        if not kids:
            return None
        for cpid, ccomm in kids:
            deeper = dfs(cpid, depth + 1)
            if deeper is None:
                # cpid is a leaf
                if best is None or depth > best[0]:
                    best = (depth, ccomm)
        return kids

    try:
        result = dfs(root, 1)
    except Exception:
        return best[1] if best else None
    if result is None:
        return None
    return best[1] if best else None


def resolve_app(mode):
    if mode == "off":
        return None
    try:
        proc = subprocess.run(
            ["hyprctl", "activewindow", "-j"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if proc.returncode != 0:
            return None
        out = (proc.stdout or "").strip()
        if not out:
            return None
        info = json.loads(out)
    except Exception:
        return None
    if not isinstance(info, dict):
        return None

    raw_class = info.get("class")
    raw_initial = info.get("initialClass")
    title = info.get("title")
    pid = info.get("pid")

    if isinstance(raw_initial, str) and raw_initial.strip():
        base_raw = raw_initial
    else:
        base_raw = raw_class

    base = _normalize_app_name(base_raw)
    if base is None:
        return None

    # steam_app_<id> -> use window title (sole title-use exception)
    if base.startswith("steam_app_"):
        return _normalize_title(title)

    if mode == "smart" and base in TERMINAL_CLASSES:
        try:
            leaf = _deepest_leaf_comm(pid)
        except Exception:
            return base
        if leaf is None:
            return base
        norm_leaf = _normalize_app_name(leaf)
        return norm_leaf if norm_leaf else base

    return base


def record(state="active"):
    if state == "idle":
        mode = load_data().get("_mode", "active")
        if mode == "active":
            print_today()
            return

    def mutate(data):
        now = datetime.datetime.now()
        date_str = now.strftime("%Y-%m-%d")
        hour_str = now.strftime("%H")

        day = data.get(date_str)
        if not isinstance(day, dict):
            day = {}
            data[date_str] = day

        cur = day.get(hour_str, 0)
        if not isinstance(cur, int):
            try:
                cur = int(cur)
            except (ValueError, TypeError):
                cur = 0

        day[hour_str] = cur + 1

    update_state(mutate)
    print_today()


def record_app(state="active"):
    settings = get_settings(load_data())
    app_mode = settings.get("app_mode", "class")

    if app_mode == "off" or state == "idle":
        print_today()
        return

    try:
        name = resolve_app(app_mode)
    except Exception:
        name = None

    if not name:
        print_today()
        return

    def mutate(data):
        now = datetime.datetime.now()
        date_str = now.strftime("%Y-%m-%d")

        day = data.get(date_str)
        if not isinstance(day, dict):
            day = {}
            data[date_str] = day

        apps = day.get("_apps")
        if not isinstance(apps, dict):
            apps = {}
            day["_apps"] = apps

        cur = apps.get(name, 0)
        if not isinstance(cur, int):
            try:
                cur = int(cur)
            except (ValueError, TypeError):
                cur = 0
        apps[name] = cur + SAMPLE_SECONDS

    update_state(mutate)
    print_today()


def toggle_mode():
    def mutate(data):
        mode = data.get("_mode", "active")
        data["_mode"] = "always" if mode == "active" else "active"

    update_state(mutate)
    print_today()


def get_settings(data):
    settings = data.get("_settings", {})
    if not isinstance(settings, dict):
        settings = {}
    return {
        "show_weekly": settings.get("show_weekly", True),
        "show_apps": settings.get("show_apps", True),
        "show_app_icons": settings.get("show_app_icons", True),
        "app_mode": settings.get("app_mode", "class"),
        "retention_days": settings.get("retention_days", 365),
    }


def toggle_weekly():
    def mutate(data):
        settings = data.get("_settings", {})
        if not isinstance(settings, dict):
            settings = {}
        settings["show_weekly"] = not settings.get("show_weekly", True)
        data["_settings"] = settings

    update_state(mutate)
    print_today()


def toggle_apps_show():
    def mutate(data):
        settings = data.get("_settings", {})
        if not isinstance(settings, dict):
            settings = {}
        settings["show_apps"] = not settings.get("show_apps", True)
        data["_settings"] = settings

    update_state(mutate)
    print_today()


def toggle_app_icons():
    def mutate(data):
        settings = data.get("_settings", {})
        if not isinstance(settings, dict):
            settings = {}
        settings["show_app_icons"] = not settings.get("show_app_icons", True)
        data["_settings"] = settings

    update_state(mutate)
    print_today()


def set_app_mode(mode):
    if mode not in APP_MODES:
        print(
            "invalid app mode: %r (expected off|class|smart)" % (mode,),
            file=sys.stderr,
        )
        sys.exit(1)
    def mutate(data):
        settings = data.get("_settings", {})
        if not isinstance(settings, dict):
            settings = {}
        settings["app_mode"] = mode
        data["_settings"] = settings

    update_state(mutate)
    print_today()


def set_retention_days(value):
    try:
        days = int(str(value).strip())
    except (ValueError, TypeError, AttributeError):
        print(
            "invalid retention days: %r (expected int)" % (value,),
            file=sys.stderr,
        )
        sys.exit(1)
    if days < 1:
        days = 1
    if days > 365:
        days = 365

    def mutate(data):
        settings = data.get("_settings", {})
        if not isinstance(settings, dict):
            settings = {}
        settings["retention_days"] = days
        data["_settings"] = settings

    update_state(mutate)
    print_today()


def get_week_data(data):
    now = datetime.datetime.now()
    days = []
    for i in range(6, -1, -1):
        day = now - datetime.timedelta(days=i)
        date_str = day.strftime("%Y-%m-%d")
        day_data = data.get(date_str, {})
        if not isinstance(day_data, dict):
            day_data = {}
        total = sum(v for v in day_data.values() if isinstance(v, int))
        days.append({
            "date": date_str,
            "label": day.strftime("%a"),
            "minutes": total,
        })
    return days


def get_apps_today(data, date_str=None):
    if date_str is None:
        date_str = datetime.datetime.now().strftime("%Y-%m-%d")
    day = data.get(date_str, {})
    if not isinstance(day, dict):
        return {"total": 0, "day_total": 0, "unattributed": 0, "apps": []}
    apps = day.get("_apps", {})
    if not isinstance(apps, dict):
        apps = {}
    items, total = collect_app_items(apps, 10, {})
    day_total = day_seconds(day)
    return {
        "total": total,
        "day_total": day_total,
        "unattributed": max(0, day_total - total),
        "apps": items,
    }


def print_today():
    data = load_data()
    now = datetime.datetime.now()
    date_str = now.strftime("%Y-%m-%d")
    today_full = data.get(date_str, {})
    if not isinstance(today_full, dict):
        today_full = {}
    total_minutes = sum(v for k, v in today_full.items() if isinstance(v, int))
    # Keep hourly chart clean: exclude _apps dict from today_data output.
    today_data = {k: v for k, v in today_full.items() if isinstance(v, int)}
    week_data = get_week_data(data)
    week_total = sum(d["minutes"] for d in week_data)
    settings = get_settings(data)
    apps_today = get_apps_today(data, date_str)
    print(json.dumps({
        "total_minutes": total_minutes,
        "today_data": today_data,
        "mode": data.get("_mode", "active"),
        "week_data": week_data,
        "week_total": week_total,
        "show_weekly": settings["show_weekly"],
        "app_mode": settings["app_mode"],
        "show_apps": settings["show_apps"],
        "show_app_icons": settings["show_app_icons"],
        "retention_days": settings["retention_days"],
        "apps_today": apps_today,
    }))


def _format_week_label(monday, sunday):
    weeknum = monday.isocalendar()[1]
    mon_name = MONTH_ABBR[monday.month - 1]
    sun_name = MONTH_ABBR[sunday.month - 1]
    if monday.year == sunday.year and monday.month == sunday.month:
        core = "%s %d \u2013 %d, %d" % (
            mon_name, monday.day, sunday.day, sunday.year
        )
    elif monday.year == sunday.year:
        core = "%s %d \u2013 %s %d, %d" % (
            mon_name, monday.day, sun_name, sunday.day, sunday.year
        )
    else:
        core = "%s %d, %d \u2013 %s %d, %d" % (
            mon_name, monday.day, monday.year,
            sun_name, sunday.day, sunday.year,
        )
    return "%s \u00b7 W%d" % (core, weeknum)


def apps_week(offset=0):
    try:
        off = int(str(offset).strip())
    except (ValueError, TypeError, AttributeError):
        print(
            "invalid week offset: %r (expected int)" % (offset,),
            file=sys.stderr,
        )
        sys.exit(1)
    data = load_data()
    retention = _get_retention_days(data)

    today = datetime.date.today()
    monday_this = today - datetime.timedelta(days=today.weekday())
    monday = monday_this + datetime.timedelta(weeks=off)
    sunday = monday + datetime.timedelta(days=6)

    week_label = _format_week_label(monday, sunday)

    days = []
    week_total = 0
    icon_cache = {}
    for i in range(7):
        d = monday + datetime.timedelta(days=i)
        date_str = d.isoformat()
        label = d.strftime("%a")
        day_data = data.get(date_str, {})
        if not isinstance(day_data, dict):
            day_data = {}
        apps_dict = day_data.get("_apps", {})
        if not isinstance(apps_dict, dict):
            apps_dict = {}
        items, total = collect_app_items(apps_dict, 8, icon_cache)
        day_total = day_seconds(day_data)
        week_total += total
        days.append({
            "date": date_str,
            "label": label,
            "total": total,
            "day_total": day_total,
            "unattributed": max(0, day_total - total),
            "apps": items,
        })

    week_share = round(100 * week_total / (7 * 24 * 3600), 1)
    # Retention clamp is implicit: missing/pruned dates yield zeros, no crash.
    _ = retention
    print(json.dumps({
        "week_label": week_label,
        "days": days,
        "week_total": week_total,
        "week_share": week_share,
    }))


if __name__ == "__main__":
    if len(sys.argv) > 1:
        cmd = sys.argv[1]
        if cmd == "record":
            state = sys.argv[2] if len(sys.argv) > 2 else "active"
            record(state)
        elif cmd in ("record-app", "record_app", "recordapp"):
            state = sys.argv[2] if len(sys.argv) > 2 else "active"
            record_app(state)
        elif cmd == "toggle":
            toggle_mode()
        elif cmd == "toggle-weekly":
            toggle_weekly()
        elif cmd in ("toggle-apps-show", "toggle_apps_show", "toggle-apps", "toggle_apps"):
            toggle_apps_show()
        elif cmd in ("toggle-app-icons", "toggle_app_icons", "toggle-icons", "toggle_icons"):
            toggle_app_icons()
        elif cmd in ("set-app-mode", "set_app_mode", "set-appmode"):
            if len(sys.argv) < 3:
                print("usage: tracker.py set-app-mode <off|class|smart>", file=sys.stderr)
                sys.exit(1)
            set_app_mode(sys.argv[2])
        elif cmd in ("set-retention-days", "set_retention_days", "set-retention", "set_retention"):
            if len(sys.argv) < 3:
                print("usage: tracker.py set-retention-days <1..365>", file=sys.stderr)
                sys.exit(1)
            set_retention_days(sys.argv[2])
        elif cmd in ("apps-week", "apps_week", "appsweek"):
            offset = sys.argv[2] if len(sys.argv) > 2 else "0"
            apps_week(offset)
        else:
            print("unknown command: %r" % (cmd,), file=sys.stderr)
            sys.exit(1)
    else:
        print_today()

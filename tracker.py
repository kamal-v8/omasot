#!/usr/bin/env python3
import json
import os
import datetime
import sys

STATE_FILE = os.path.expanduser("~/.local/state/screentime.json")

def load_data():
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE, "r") as f:
            try:
                return json.load(f)
            except (json.JSONDecodeError, ValueError):
                pass
    return {}

def save_data(data):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    tmp_file = STATE_FILE + ".tmp"
    with open(tmp_file, "w") as f:
        json.dump(data, f)
    os.replace(tmp_file, STATE_FILE)

def record(state="active"):
    data = load_data()
    mode = data.get("_mode", "active")
    
    if state == "idle" and mode == "active":
        print_today()
        return

    now = datetime.datetime.now()
    date_str = now.strftime("%Y-%m-%d")
    hour_str = now.strftime("%H")
    
    if date_str not in data:
        data[date_str] = {}
    
    if hour_str not in data[date_str]:
        data[date_str][hour_str] = 0
        
    data[date_str][hour_str] += 1
    # Prune entries older than 30 days
    cutoff = (now - datetime.timedelta(days=30)).strftime("%Y-%m-%d")
    data = {k: v for k, v in data.items() if k >= cutoff or k == "_mode"}
    save_data(data)
    print_today()

def toggle_mode():
    data = load_data()
    mode = data.get("_mode", "active")
    data["_mode"] = "always" if mode == "active" else "active"
    save_data(data)
    print_today()

def print_today():
    data = load_data()
    now = datetime.datetime.now()
    date_str = now.strftime("%Y-%m-%d")
    today_data = data.get(date_str, {})
    total_minutes = sum(v for k, v in today_data.items() if isinstance(v, int))
    print(json.dumps({
        "total_minutes": total_minutes,
        "today_data": today_data,
        "mode": data.get("_mode", "active")
    }))

if __name__ == "__main__":
    if len(sys.argv) > 1:
        if sys.argv[1] == "record":
            state = sys.argv[2] if len(sys.argv) > 2 else "active"
            record(state)
        elif sys.argv[1] == "toggle":
            toggle_mode()
    else:
        print_today()

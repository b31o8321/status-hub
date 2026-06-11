from __future__ import annotations

from datetime import datetime
from pathlib import Path
import argparse
import json
import os
import re
import signal
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request


DEFAULT_CONFIG = {
    "refreshIntervalSeconds": 10,
    "checks": {
        "ports": [
            {"port": 3000, "title": "web", "required": False},
            {"port": 5173, "title": "vite", "required": False},
            {"port": 8000, "title": "api", "required": False},
            {"port": 8080, "title": "api", "required": False},
            {"port": 5432, "title": "postgres", "required": False},
            {"port": 6379, "title": "redis", "required": False},
            {"port": 9200, "title": "elasticsearch", "required": False},
        ],
        "urls": [],
        "processes": [
            {"pattern": "Docker", "title": "Docker", "required": False},
            {"pattern": "colima", "title": "Colima", "required": False},
        ],
    },
}


SEVERITY = {
    "idle": 0,
    "unknown": 0,
    "success": 1,
    "running": 3,
    "attention": 4,
    "failed": 5,
}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Status Hub local services provider")
    parser.add_argument("--once", action="store_true", help="write status once and exit")
    parser.add_argument("--interval", type=float, default=None, help="poll interval in seconds")
    args = parser.parse_args(argv)

    status_file = Path(os.environ.get("STATUS_HUB_STATUS_FILE", "runtime/status.json")).expanduser()
    config_file = os.environ.get("STATUS_HUB_CONFIG_FILE")
    config = load_config(Path(config_file).expanduser() if config_file else None)
    interval = args.interval or float(config.get("refreshIntervalSeconds", 10))

    stopped = False

    def stop(_signum, _frame):
        nonlocal stopped
        stopped = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    while not stopped:
        snapshot = build_snapshot(config)
        write_json(status_file, snapshot)
        if args.once:
            return 0
        time.sleep(max(interval, 2.0))

    return 0


def load_config(config_file: Path | None) -> dict:
    config = json.loads(json.dumps(DEFAULT_CONFIG))
    if not config_file or not config_file.exists():
        return config
    try:
        data = json.loads(config_file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return config
    return deep_merge(config, data)


def deep_merge(base: dict, override: dict) -> dict:
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            base[key] = deep_merge(base[key], value)
        else:
            base[key] = value
    return base


def build_snapshot(config: dict) -> dict:
    checks = config.get("checks", {})
    items = []
    items.extend(check_port(item) for item in parse_ports(checks.get("ports", [])))
    items.extend(check_url(item) for item in parse_urls(checks.get("urls", [])))
    items.extend(check_process(item) for item in parse_processes(checks.get("processes", [])))

    status = overall_status(items)
    summary = build_summary(items)
    return {
        "status": status,
        "summary": summary,
        "updatedAt": datetime.now().astimezone().isoformat(timespec="seconds"),
        "items": items,
    }


def parse_ports(value) -> list[dict]:
    if isinstance(value, list):
        return [
            {
                "port": int(item.get("port", 0)),
                "title": str(item.get("title") or item.get("name") or f"port {item.get('port')}"),
                "host": str(item.get("host") or "127.0.0.1"),
                "required": bool(item.get("required", False)),
            }
            for item in value
            if isinstance(item, dict) and item.get("port")
        ]
    rows = parse_lines(value)
    ports = []
    for row in rows:
        parts = split_check_line(row)
        if not parts:
            continue
        try:
            port = int(parts[0])
        except ValueError:
            continue
        ports.append(
            {
                "port": port,
                "title": parts[1] if len(parts) > 1 and parts[1] else f"port {port}",
                "host": "127.0.0.1",
                "required": parse_bool(parts[2] if len(parts) > 2 else "false"),
            }
        )
    return ports


def parse_urls(value) -> list[dict]:
    if isinstance(value, list):
        return [
            {
                "url": str(item.get("url")),
                "title": str(item.get("title") or item.get("name") or item.get("url")),
                "required": bool(item.get("required", False)),
            }
            for item in value
            if isinstance(item, dict) and item.get("url")
        ]
    rows = parse_lines(value)
    urls = []
    for row in rows:
        match = re.match(r"^(https?://\S+?)(?::([^:\n]+))?(?::(true|false|yes|no|1|0))?$", row, re.IGNORECASE)
        if not match:
            continue
        url = match.group(1)
        urls.append(
            {
                "url": url,
                "title": match.group(2) or url,
                "required": parse_bool(match.group(3) or "false"),
            }
        )
    return urls


def parse_processes(value) -> list[dict]:
    if isinstance(value, list):
        return [
            {
                "pattern": str(item.get("pattern") or item.get("name")),
                "title": str(item.get("title") or item.get("name") or item.get("pattern")),
                "required": bool(item.get("required", False)),
            }
            for item in value
            if isinstance(item, dict) and (item.get("pattern") or item.get("name"))
        ]
    rows = parse_lines(value)
    processes = []
    for row in rows:
        parts = split_check_line(row)
        if not parts:
            continue
        processes.append(
            {
                "pattern": parts[0],
                "title": parts[1] if len(parts) > 1 and parts[1] else parts[0],
                "required": parse_bool(parts[2] if len(parts) > 2 else "false"),
            }
        )
    return processes


def parse_lines(value) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        trimmed = value.strip()
        if not trimmed:
            return []
        if trimmed.startswith("["):
            try:
                parsed = json.loads(trimmed)
                if isinstance(parsed, list):
                    return [json.dumps(item) if isinstance(item, dict) else str(item) for item in parsed]
            except json.JSONDecodeError:
                pass
        return [line.strip() for line in trimmed.splitlines() if line.strip() and not line.strip().startswith("#")]
    return []


def split_check_line(row: str) -> list[str]:
    if row.startswith("{"):
        try:
            data = json.loads(row)
        except json.JSONDecodeError:
            return []
        if "port" in data:
            return [str(data.get("port")), str(data.get("title") or data.get("name") or ""), str(data.get("required", False))]
        if "pattern" in data or "name" in data:
            return [str(data.get("pattern") or data.get("name")), str(data.get("title") or data.get("name") or ""), str(data.get("required", False))]
    return [part.strip() for part in row.split(":")]


def parse_bool(value) -> bool:
    return str(value).strip().lower() in {"true", "yes", "y", "1", "required"}


def check_port(item: dict) -> dict:
    port = item["port"]
    host = item.get("host", "127.0.0.1")
    title = item.get("title", f"port {port}")
    required = item.get("required", False)
    alive = can_connect(host, port)
    status = "success" if alive else "attention" if required else "idle"
    subtitle = f"{host}:{port} {'listening' if alive else 'closed'}"
    return {
        "id": f"port-{port}",
        "title": title,
        "subtitle": subtitle,
        "status": status,
        "value": "up" if alive else "down",
        "detail": {"type": "port", "host": host, "port": str(port), "required": str(required).lower()},
    }


def check_url(item: dict) -> dict:
    url = item["url"]
    title = item.get("title", url)
    required = item.get("required", False)
    started = time.monotonic()
    try:
        request = urllib.request.Request(url, method="GET", headers={"User-Agent": "StatusHub/LocalServices"})
        with urllib.request.urlopen(request, timeout=3) as response:
            code = response.getcode()
        elapsed_ms = int((time.monotonic() - started) * 1000)
        ok = 200 <= code < 400
        status = "success" if ok else "attention" if required else "idle"
        subtitle = f"HTTP {code} · {elapsed_ms} ms"
        value = str(code)
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        status = "attention" if required else "idle"
        subtitle = f"unreachable · {short_error(exc)}"
        value = "down"
    return {
        "id": stable_id("url", url),
        "title": title,
        "subtitle": subtitle,
        "status": status,
        "url": url,
        "value": value,
        "detail": {"type": "http", "required": str(required).lower()},
    }


def check_process(item: dict) -> dict:
    pattern = item["pattern"]
    title = item.get("title", pattern)
    required = item.get("required", False)
    count = process_count(pattern)
    alive = count > 0
    status = "success" if alive else "attention" if required else "idle"
    return {
        "id": stable_id("process", pattern),
        "title": title,
        "subtitle": f"{count} matching process{'es' if count != 1 else ''}",
        "status": status,
        "value": "up" if alive else "down",
        "detail": {"type": "process", "pattern": pattern, "required": str(required).lower()},
    }


def can_connect(host: str, port: int) -> bool:
    try:
        with socket.create_connection((host, port), timeout=0.6):
            return True
    except OSError:
        return False


def process_count(pattern: str) -> int:
    try:
        result = subprocess.run(
            ["/bin/ps", "-axo", "pid=,ppid=,command="],
            check=False,
            capture_output=True,
            text=True,
            timeout=3,
        )
    except (OSError, subprocess.TimeoutExpired):
        return 0
    ignored_pids = ancestor_pids(result.stdout)
    pattern_lower = pattern.lower()
    count = 0
    for line in result.stdout.splitlines():
        parsed = parse_process_line(line)
        if not parsed:
            continue
        pid, _ppid, command = parsed
        if pid in ignored_pids:
            continue
        if pattern_lower in command.lower():
            count += 1
    return count


def ancestor_pids(ps_output: str) -> set[int]:
    parents: dict[int, int] = {}
    for line in ps_output.splitlines():
        parsed = parse_process_line(line)
        if not parsed:
            continue
        pid, ppid, _command = parsed
        parents[pid] = ppid
    ignored = {os.getpid()}
    current = os.getpid()
    while current in parents and parents[current] > 0:
        current = parents[current]
        ignored.add(current)
    return ignored


def parse_process_line(line: str) -> tuple[int, int, str] | None:
    parts = line.strip().split(None, 2)
    if len(parts) < 3:
        return None
    try:
        return int(parts[0]), int(parts[1]), parts[2]
    except ValueError:
        return None


def overall_status(items: list[dict]) -> str:
    if any(item.get("status") == "attention" for item in items):
        return "attention"
    if any(item.get("status") == "success" for item in items):
        return "success"
    return "idle"


def build_summary(items: list[dict]) -> str:
    running = sum(1 for item in items if item.get("status") == "success")
    failed_required = sum(1 for item in items if item.get("status") == "attention")
    observed = len(items)
    if failed_required:
        return f"{failed_required} required check{'s' if failed_required != 1 else ''} down · {running}/{observed} up"
    if running:
        return f"{running}/{observed} observed services up"
    return f"{observed} checks configured · no observed services up"


def stable_id(prefix: str, value: str) -> str:
    normalized = re.sub(r"[^a-zA-Z0-9_.-]+", "-", value.strip().lower()).strip("-")
    return f"{prefix}-{normalized[:48] or 'item'}"


def short_error(exc: Exception) -> str:
    message = str(exc)
    return message[:80] if message else exc.__class__.__name__


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
        tmp_name = handle.name
    os.replace(tmp_name, path)

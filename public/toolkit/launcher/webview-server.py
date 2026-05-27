#!/usr/bin/env python3
"""
Codex Desktop - Cross-platform Webview HTTP Server (Windows-compatible)

Serves the webview content directory over HTTP for the Electron shell to load.
Designed to work on Windows, macOS, and Linux.

Key differences from the Linux version:
- Uses ThreadingHTTPServer for concurrent requests
- No prctl/Linux-specific parent-death detection
- Uses atexit and Windows Job Objects for cleanup
- Proper signal handling for SIGTERM/SIGINT on Windows
- Windows-compatible path handling
"""

import argparse
import atexit
import http.server
import os
import signal
import socket
import socketserver
import sys
import threading
import time
import json
import functools
from pathlib import Path
from typing import Optional


# ─── Configuration ────────────────────────────────────────────────────────────

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 5175
SERVER_VERSION = "CodexDesktop-Webview/1.0"

# ─── Custom HTTP Request Handler ──────────────────────────────────────────────


class WebviewHandler(http.server.SimpleHTTPRequestHandler):
    """Custom HTTP handler that serves webview content with proper headers."""

    server_version = SERVER_VERSION

    def __init__(self, *args, content_dir: str = None, **kwargs):
        self._content_dir = content_dir
        if content_dir:
            # Change to content directory so SimpleHTTPRequestHandler serves from it
            os.chdir(content_dir)
        super().__init__(*args, **kwargs)

    def end_headers(self):
        """Add cache-control and security headers."""
        # Prevent caching - always serve fresh content
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")

        # Security headers
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "SAMEORIGIN")

        super().end_headers()

    def do_GET(self):
        """Handle GET requests with SPA fallback."""
        # Parse path
        parsed_path = self.path.split("?")[0].split("#")[0]

        # Try exact file first
        file_path = Path(".") / parsed_path.lstrip("/")
        if file_path.is_file():
            return super().do_GET()

        # SPA fallback: serve index.html for non-file paths
        index_path = Path(".") / "index.html"
        if index_path.is_file():
            self.path = "/index.html"
            return super().do_GET()

        # No fallback available
        self.send_error(404, f"File not found: {parsed_path}")

    def do_POST(self):
        """Handle POST requests (for IPC communication)."""
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length > 0 else b""

        # Route: /api/health
        if self.path == "/api/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            health = {
                "status": "ok",
                "server": SERVER_VERSION,
                "pid": os.getpid(),
                "uptime": time.time() - _start_time,
            }
            self.wfile.write(json.dumps(health).encode())
            return

        # Route: /api/shutdown
        if self.path == "/api/shutdown":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"status": "shutting_down"}).encode())
            # Schedule shutdown
            threading.Thread(target=_shutdown_server, daemon=True).start()
            return

        self.send_error(404, "Not found")

    def log_message(self, format, *args):
        """Override to use structured logging."""
        message = format % args
        sys.stderr.write(
            json.dumps({
                "type": "http",
                "method": self.command,
                "path": self.path,
                "message": message,
                "timestamp": time.time(),
            }) + "\n"
        )

    def do_OPTIONS(self):
        """Handle CORS preflight requests."""
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "http://127.0.0.1:*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Max-Age", "86400")
        self.end_headers()


# ─── Threaded Server ──────────────────────────────────────────────────────────


class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    """HTTP server that handles each request in a separate thread."""

    daemon_threads = True
    allow_reuse_address = True

    def server_bind(self):
        """Bind with SO_REUSEADDR for faster port release."""
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        super().server_bind()


# ─── Parent Process Monitoring ────────────────────────────────────────────────

_parent_pid: Optional[int] = None
_server_instance: Optional[ThreadedHTTPServer] = None


def _monitor_parent():
    """
    Monitor parent process and exit if it dies.
    On Windows, we use polling since prctl is Linux-specific.
    """
    global _parent_pid
    if _parent_pid is None:
        return

    while True:
        try:
            if _parent_pid == 0:
                # Parent is init/launchd, don't monitor
                break

            # Check if parent is still alive
            parent_alive = False
            try:
                if sys.platform == "win32":
                    import ctypes
                    kernel32 = ctypes.windll.kernel32
                    PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
                    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, _parent_pid)
                    if handle:
                        kernel32.CloseHandle(handle)
                        parent_alive = True
                else:
                    os.kill(_parent_pid, 0)
                    parent_alive = True
            except (ProcessLookupError, PermissionError, OSError):
                parent_alive = False

            if not parent_alive:
                print(f"Parent process {_parent_pid} died, shutting down server", file=sys.stderr)
                _shutdown_server()
                break

        except Exception as e:
            print(f"Error monitoring parent: {e}", file=sys.stderr)

        time.sleep(2)


def _setup_job_object():
    """
    On Windows, associate the process with a Job Object so that if the
    parent process dies, this process is also terminated.
    """
    if sys.platform != "win32":
        return

    try:
        import ctypes
        from ctypes import wintypes

        kernel32 = ctypes.windll.kernel32

        # Create a Job Object
        JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000
        JobObjectExtendedLimitInformation = 9

        job = kernel32.CreateJobObjectW(None, None)
        if not job:
            return

        # Set JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        class JOBOBJECT_BASIC_LIMIT_INFORMATION(ctypes.Structure):
            _fields_ = [
                ("PerProcessUserTimeLimit", wintypes.LARGE_INTEGER),
                ("PerJobUserTimeLimit", wintypes.LARGE_INTEGER),
                ("LimitFlags", wintypes.DWORD),
                ("MinimumWorkingSetSize", ctypes.c_size_t),
                ("MaximumWorkingSetSize", ctypes.c_size_t),
                ("ActiveProcessLimit", wintypes.DWORD),
                ("Affinity", ctypes.POINTER(wintypes.ULONG)),
                ("PriorityClass", wintypes.DWORD),
                ("SchedulingClass", wintypes.DWORD),
            ]

        class IO_COUNTERS(ctypes.Structure):
            _fields_ = [
                ("ReadOperationCount", ctypes.c_uint64),
                ("WriteOperationCount", ctypes.c_uint64),
                ("OtherOperationCount", ctypes.c_uint64),
                ("ReadTransferCount", ctypes.c_uint64),
                ("WriteTransferCount", ctypes.c_uint64),
                ("OtherTransferCount", ctypes.c_uint64),
            ]

        class JOBOBJECT_EXTENDED_LIMIT_INFORMATION(ctypes.Structure):
            _fields_ = [
                ("BasicLimitInformation", JOBOBJECT_BASIC_LIMIT_INFORMATION),
                ("IoInfo", IO_COUNTERS),
                ("ProcessMemoryLimit", ctypes.c_size_t),
                ("JobMemoryLimit", ctypes.c_size_t),
                ("PeakProcessMemoryUsed", ctypes.c_size_t),
                ("PeakJobMemoryUsed", ctypes.c_size_t),
            ]

        info = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
        info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE

        kernel32.SetInformationJobObject(
            job,
            JobObjectExtendedLimitInformation,
            ctypes.byref(info),
            ctypes.sizeof(info),
        )

        # Assign our process to the job
        current_process = kernel32.GetCurrentProcess()
        kernel32.AssignProcessToJobObject(job, current_process)

    except Exception as e:
        print(f"Could not set up Job Object: {e}", file=sys.stderr)


# ─── Server Lifecycle ─────────────────────────────────────────────────────────

_start_time = time.time()


def _shutdown_server():
    """Gracefully shut down the HTTP server."""
    global _server_instance
    if _server_instance:
        print("Shutting down webview server...", file=sys.stderr)
        threading.Thread(target=_server_instance.shutdown, daemon=True).start()


def _signal_handler(signum, frame):
    """Handle termination signals."""
    signal_name = signal.Signals(signum).name if hasattr(signal, "Signals") else str(signum)
    print(f"Received signal {signal_name}, shutting down...", file=sys.stderr)
    _shutdown_server()
    sys.exit(0)


def _atexit_handler():
    """Cleanup handler registered with atexit."""
    _shutdown_server()


# ─── Port Availability ────────────────────────────────────────────────────────

def check_port_available(host: str, port: int) -> bool:
    """Check if a port is available for binding."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind((host, port))
            return True
    except OSError:
        return False


def find_available_port(host: str, start_port: int, max_port: int = 65535) -> int:
    """Find the next available port starting from start_port."""
    for port in range(start_port, max_port + 1):
        if check_port_available(host, port):
            return port
    raise RuntimeError(f"No available port in range {start_port}-{max_port}")


# ─── Main ─────────────────────────────────────────────────────────────────────


def main():
    global _parent_pid, _server_instance

    parser = argparse.ArgumentParser(
        description="Codex Desktop Webview HTTP Server"
    )
    parser.add_argument(
        "--host", default=DEFAULT_HOST,
        help=f"Host to bind to (default: {DEFAULT_HOST})"
    )
    parser.add_argument(
        "--port", type=int, default=DEFAULT_PORT,
        help=f"Port to bind to (default: {DEFAULT_PORT})"
    )
    parser.add_argument(
        "--directory", "-d", default=None,
        help="Directory to serve webview content from"
    )
    parser.add_argument(
        "--parent-pid", type=int, default=None,
        help="Parent process PID to monitor"
    )
    parser.add_argument(
        "--find-port", action="store_true",
        help="Automatically find an available port if default is taken"
    )
    args = parser.parse_args()

    # Determine content directory
    content_dir = args.directory
    if not content_dir:
        # Try to find content relative to script location
        script_dir = Path(__file__).parent.resolve()
        candidates = [
            script_dir / "content" / "webview",
            script_dir / ".." / "content" / "webview",
            script_dir / "webview",
            Path.cwd() / "content" / "webview",
        ]
        for candidate in candidates:
            candidate = candidate.resolve()
            if candidate.is_dir():
                content_dir = str(candidate)
                break

        if not content_dir:
            print("Warning: No webview content directory found, serving current directory", file=sys.stderr)
            content_dir = str(Path.cwd())

    content_dir = str(Path(content_dir).resolve())

    if not Path(content_dir).is_dir():
        print(f"Error: Content directory does not exist: {content_dir}", file=sys.stderr)
        sys.exit(1)

    # Port handling
    port = args.port
    if args.find_port and not check_port_available(args.host, port):
        port = find_available_port(args.host, port + 1)
        print(f"Port {args.port} is in use, using port {port}", file=sys.stderr)

    # Setup parent monitoring
    _parent_pid = args.parent_pid
    if _parent_pid:
        monitor_thread = threading.Thread(target=_monitor_parent, daemon=True)
        monitor_thread.start()

    # Setup Job Object on Windows
    _setup_job_object()

    # Register signal handlers
    signal.signal(signal.SIGTERM, _signal_handler)
    signal.signal(signal.SIGINT, _signal_handler)
    if sys.platform == "win32":
        # On Windows, also handle SIGBREAK
        try:
            signal.signal(signal.SIGBREAK, _signal_handler)
        except (AttributeError, OSError):
            pass

    # Register atexit handler
    atexit.register(_atexit_handler)

    # Create handler factory with content_dir
    handler_class = functools.partial(WebviewHandler, content_dir=content_dir)

    # Create and start server
    try:
        _server_instance = ThreadedHTTPServer((args.host, port), handler_class)
    except OSError as e:
        if "Address already in use" in str(e) or e.errno == 10048:
            print(f"Error: Port {port} is already in use", file=sys.stderr)
            sys.exit(1)
        raise

    # Output ready signal (for process orchestrators)
    ready_info = json.dumps({
        "status": "ready",
        "host": args.host,
        "port": port,
        "pid": os.getpid(),
        "content_dir": content_dir,
    })
    print(f"WEBVIEW_SERVER_READY: {ready_info}", file=sys.stderr)

    try:
        _server_instance.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        _shutdown_server()

    print("Webview server stopped.", file=sys.stderr)


if __name__ == "__main__":
    main()

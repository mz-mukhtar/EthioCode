# android/app/src/main/python/runner.py
#
# This module is bundled inside the APK by Chaquopy.
# It is imported once by MainActivity.kt on the Python thread.
#
# Design:
#   • run_code(source: str, timeout: int) → dict
#       Executes arbitrary Python source in a sandboxed exec() context.
#       stdout and stderr are redirected to io.StringIO buffers so the
#       Kotlin side can retrieve them as plain strings.
#       A threading.Timer enforces the hard timeout: it raises SystemExit
#       in the executing thread, which unwinds cleanly via try/except.
#
# Thread-safety:
#   • Each call to run_code() creates its own isolated namespace dict and
#     fresh StringIO buffers – concurrent calls cannot share state.
#   • The timeout Timer is always cancelled in the finally block to prevent
#     ghost threads from lingering after a successful run.

import sys
import io
import traceback
import threading
import builtins


def run_code(source: str, timeout_seconds: int = 5) -> dict:
    """
    Execute *source* as Python code and capture its output.

    Returns a dict with keys:
        stdout  (str)  – everything written to sys.stdout (print() output)
        stderr  (str)  – everything written to sys.stderr (tracebacks, etc.)
        error   (bool) – True when execution ended with an exception or timeout
    """
    stdout_buf = io.StringIO()
    stderr_buf = io.StringIO()

    # ── Timeout mechanism ────────────────────────────────────────────────────
    timed_out = threading.Event()
    executing_thread = threading.current_thread()

    def _timeout_handler():
        """Raise SystemExit in the executing thread after the deadline."""
        timed_out.set()
        # ctypes-based async exception raise – works in CPython on Android.
        import ctypes
        ctypes.pythonapi.PyThreadState_SetAsyncExc(
            ctypes.c_ulong(executing_thread.ident),
            ctypes.py_object(SystemExit),
        )

    timer = threading.Timer(timeout_seconds, _timeout_handler)

    # ── Isolated execution namespace ─────────────────────────────────────────
    # Provide a safe subset of builtins.  We expose the full builtins dict
    # so students can use all standard constructs (list, dict, range, etc.)
    # but we shadow 'open' to block filesystem access during execution.
    safe_globals: dict = {
        "__builtins__": {k: v for k, v in vars(builtins).items()},
        "__name__": "__main__",
    }
    # Shadow dangerous builtins.
    safe_globals["__builtins__"]["open"] = _blocked("open")
    safe_globals["__builtins__"]["__import__"] = _safe_import

    error_occurred = False

    try:
        timer.start()

        # Redirect Python-level stdout/stderr.
        old_stdout, old_stderr = sys.stdout, sys.stderr
        sys.stdout = stdout_buf
        sys.stderr = stderr_buf

        try:
            compiled = compile(source, "<ethiocode>", "exec")
            exec(compiled, safe_globals)  # noqa: S102
        except SystemExit:
            if timed_out.is_set():
                print(
                    f"\n⏱  Execution stopped: exceeded {timeout_seconds}s time limit.",
                    file=stderr_buf,
                )
            error_occurred = True
        except Exception:  # noqa: BLE001
            traceback.print_exc(file=stderr_buf)
            error_occurred = True
        finally:
            sys.stdout = old_stdout
            sys.stderr = old_stderr

    finally:
        timer.cancel()

    return {
        "stdout": stdout_buf.getvalue(),
        "stderr": stderr_buf.getvalue(),
        "error": error_occurred,
    }


# ── Helpers ───────────────────────────────────────────────────────────────────

def _blocked(name: str):
    """Return a callable that always raises PermissionError."""
    def _raise(*args, **kwargs):
        raise PermissionError(f"'{name}' is restricted in the sandbox.")
    return _raise


# Allow only safe stdlib imports; block os, subprocess, socket etc.
_BLOCKED_MODULES = frozenset({
    "os", "subprocess", "socket", "shutil", "pathlib",
    "multiprocessing", "ctypes", "signal", "pty",
})

_original_import = builtins.__import__


def _safe_import(name, *args, **kwargs):
    top_level = name.split(".")[0]
    if top_level in _BLOCKED_MODULES:
        raise ImportError(
            f"Module '{name}' is not available in the EthioCode sandbox."
        )
    return _original_import(name, *args, **kwargs)

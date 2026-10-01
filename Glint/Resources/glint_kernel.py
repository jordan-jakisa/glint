"""Glint's bridge to a Jupyter kernel.

Glint runs this with a Python that has jupyter_client and ipykernel. It
starts the notebook's kernel and speaks JSON lines: requests on stdin,
outputs on stdout, in nbformat's own shapes so Glint can save them as is.

  in:  {"id": "...", "code": "..."}   run a cell
       {"cmd": "interrupt"} | {"cmd": "restart"} | {"cmd": "shutdown"}
  out: {"type": "ready"} | {"type": "restarted"} | {"type": "fatal", "message": "..."}
       {"type": "output", "id": ..., "output": {...}} | {"type": "clear", "id": ...}
       {"type": "done", "id": ..., "execution_count": n, "status": "ok" | "error"}
"""

import json
import queue
import sys
import threading

_lock = threading.Lock()


def send(message):
    with _lock:
        sys.stdout.write(json.dumps(message) + "\n")
        sys.stdout.flush()


try:
    from jupyter_client.manager import KernelManager
except Exception as error:  # noqa: BLE001
    send({"type": "fatal", "message": "jupyter_client isn't installed: %s" % error})
    sys.exit(2)

kernel_name = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else "python3"
cwd = sys.argv[2] if len(sys.argv) > 2 else None


def start(name):
    manager = KernelManager(kernel_name=name)
    manager.start_kernel(cwd=cwd)
    return manager


try:
    km = start(kernel_name)
except Exception:  # noqa: BLE001
    # The notebook names a kernel this Python doesn't have; use its own.
    try:
        km = start("python3")
    except Exception as error:  # noqa: BLE001
        send({"type": "fatal", "message": "Couldn't start a kernel: %s" % error})
        sys.exit(3)

kc = km.client()
kc.start_channels()
try:
    kc.wait_for_ready(timeout=60)
except Exception as error:  # noqa: BLE001
    send({"type": "fatal", "message": "The kernel didn't start: %s" % error})
    sys.exit(4)
send({"type": "ready"})

jobs = queue.Queue()


def read_requests():
    for line in sys.stdin:
        try:
            request = json.loads(line)
        except ValueError:
            continue
        command = request.get("cmd")
        if command == "interrupt":
            km.interrupt_kernel()
        elif command == "shutdown":
            break
        else:
            jobs.put(request)
    jobs.put(None)


threading.Thread(target=read_requests, daemon=True).start()

while True:
    job = jobs.get()
    if job is None:
        break
    if job.get("cmd") == "restart":
        km.restart_kernel(now=True)
        kc.wait_for_ready(timeout=60)
        send({"type": "restarted"})
        continue
    request_id = job["id"]
    msg_id = kc.execute(job["code"], store_history=True, allow_stdin=False)
    count = None
    status = "ok"
    while True:
        try:
            message = kc.get_iopub_msg(timeout=1)
        except queue.Empty:
            if not km.is_alive():
                status = "error"
                send({"type": "output", "id": request_id, "output": {
                    "output_type": "error", "ename": "KernelDied",
                    "evalue": "The kernel stopped. Restart it to go on.", "traceback": []}})
                break
            continue
        if message.get("parent_header", {}).get("msg_id") != msg_id:
            continue
        kind = message["msg_type"]
        content = message["content"]
        if kind == "stream":
            send({"type": "output", "id": request_id, "output": {
                "output_type": "stream", "name": content["name"], "text": content["text"]}})
        elif kind in ("execute_result", "display_data"):
            output = {"output_type": kind, "data": content.get("data", {}), "metadata": content.get("metadata", {})}
            if kind == "execute_result":
                output["execution_count"] = content.get("execution_count")
            send({"type": "output", "id": request_id, "output": output})
        elif kind == "error":
            status = "error"
            send({"type": "output", "id": request_id, "output": {
                "output_type": "error", "ename": content["ename"], "evalue": content["evalue"],
                "traceback": content["traceback"]}})
        elif kind == "execute_input":
            count = content.get("execution_count")
        elif kind == "clear_output":
            send({"type": "clear", "id": request_id})
        elif kind == "status" and content.get("execution_state") == "idle":
            break
    send({"type": "done", "id": request_id, "execution_count": count, "status": status})

kc.stop_channels()
km.shutdown_kernel(now=True)
# Skip interpreter teardown: jupyter_client's finalizers log into a closed
# logging module there.
sys.stdout.flush()
import os  # noqa: E402

os._exit(0)

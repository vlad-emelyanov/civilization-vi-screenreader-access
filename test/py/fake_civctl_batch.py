"""A fake `civctl batch` for test_civregress: reads JSON-array command lines on stdin, prints output and `@@CIVCTL-DONE <rc>`."""
import json
import os
import sys
import time

for raw in sys.stdin:
    args = json.loads(raw)
    cmd = args[0]
    if cmd == "pid":
        print("pid %d" % os.getpid())
    elif cmd == "key":
        print("SR> spoken")
        print("@@waited 300")
        print("@@waited 120")
    elif cmd == "crash":
        print("GAME CRASHED")
        print("@@CIVCTL-DONE 5")
        sys.stdout.flush()
        continue
    elif cmd == "die":
        print("half an answer")
        sys.stdout.flush()
        os._exit(3)
    elif cmd == "silent-die":
        os._exit(3)
    elif cmd == "hang":
        sys.stdout.flush()
        time.sleep(60)
    elif cmd == "fail":
        print("nope")
        print("@@CIVCTL-DONE 1")
        sys.stdout.flush()
        continue
    else:
        print("echo " + " ".join(args))
    print("@@CIVCTL-DONE 0")
    sys.stdout.flush()

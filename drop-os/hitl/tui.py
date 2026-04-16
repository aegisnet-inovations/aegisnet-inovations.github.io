import os
import time
import subprocess

QUEUE = "/var/drop-os/hitl_queue.diff"


def main():
    os.makedirs("/var/drop-os", exist_ok=True)
    open(QUEUE, "a").close()

    while True:
        if os.path.getsize(QUEUE) > 0:
            print("DROP HITL: proposed system patch detected.")
            with open(QUEUE) as f:
                diff = f.read()
            print("Diff:\n", diff)
            ans = input("Apply patch? [y/N]: ").strip().lower()
            if ans == "y":
                proc = subprocess.Popen(["patch", "-p1"], stdin=subprocess.PIPE, text=True)
                proc.communicate(diff)
                print("Patch applied.")
            else:
                print("Patch rejected.")
            open(QUEUE, "w").close()
        time.sleep(5)


if __name__ == "__main__":
    main()

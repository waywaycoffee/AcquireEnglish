"""Sample GPU utilization while running a real voice-session test."""

import argparse
import csv
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=int, default=120)
    args = parser.parse_args()
    if args.seconds < 1:
        parser.error("--seconds must be positive")

    fields = "index,name,memory.total,memory.used,utilization.gpu"
    command = ["nvidia-smi", f"--query-gpu={fields}", "--format=csv,noheader,nounits"]
    print("elapsed_s,gpu_index,gpu,memory_total_mib,memory_used_mib,gpu_percent", flush=True)
    started = time.monotonic()
    while (elapsed := time.monotonic() - started) < args.seconds:
        sample = subprocess.check_output(command, text=True, timeout=5)
        for row in csv.reader(sample.splitlines(), skipinitialspace=True):
            print(f"{elapsed:.2f}," + ",".join(row), flush=True)
        time.sleep(1)


if __name__ == "__main__":
    main()

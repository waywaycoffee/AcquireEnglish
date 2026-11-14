import sys
from pathlib import Path

paths = sys.argv[1:] or ["/tmp/pg_finish_now.sh"]
for raw in paths:
    p = Path(raw)
    data = p.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"")
    out = p if p.name.endswith("_clean.sh") else p.with_name(p.stem + "_clean.sh")
    if raw.endswith("_clean.sh") or "--inplace" in sys.argv:
        out = p
    out.write_bytes(data)
    print("wrote", out, "bytes", len(data))

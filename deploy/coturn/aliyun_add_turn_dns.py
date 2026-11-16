#!/usr/bin/env python3
"""Add turn.curlhairai.com A record. Noninteractive."""
from __future__ import annotations

import hashlib
import hmac
import base64
import json
import os
import time
import uuid
import urllib.parse
import urllib.request

AK = os.environ["ALIYUN_ACCESS_KEY_ID"]
SK = os.environ["ALIYUN_ACCESS_KEY_SECRET"]
DOMAIN = os.environ.get("DNS_DOMAIN", "curlhairai.com")
RR = os.environ.get("DNS_RR", "turn")
VALUE = os.environ.get("DNS_VALUE", "8.163.45.100")


def sign(params: dict, sk: str) -> str:
    qs = "&".join(
        f"{urllib.parse.quote(k, safe='')}={urllib.parse.quote(params[k], safe='')}"
        for k in sorted(params)
    )
    string_to_sign = "GET&%2F&" + urllib.parse.quote(qs, safe="")
    dig = hmac.new((sk + "&").encode(), string_to_sign.encode(), hashlib.sha1).digest()
    return base64.b64encode(dig).decode()


def call(action: str, extra: dict) -> dict:
    params = {
        "Format": "JSON",
        "Version": "2015-01-09",
        "AccessKeyId": AK,
        "SignatureMethod": "HMAC-SHA1",
        "Timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "SignatureVersion": "1.0",
        "SignatureNonce": str(uuid.uuid4()),
        "Action": action,
    }
    params.update(extra)
    params["Signature"] = sign(params, SK)
    url = "https://alidns.aliyuncs.com/?" + urllib.parse.urlencode(params)
    try:
        with urllib.request.urlopen(url, timeout=20) as r:
            return json.loads(r.read().decode())
    except Exception as e:  # noqa: BLE001
        if hasattr(e, "read"):
            return json.loads(e.read().decode())
        return {"error": str(e)}


def main() -> int:
    listed = call(
        "DescribeDomainRecords",
        {"DomainName": DOMAIN, "RRKeyWord": RR, "Type": "A", "PageSize": "50"},
    )
    records = (listed.get("DomainRecords") or {}).get("Record") or []
    for rec in records:
        if rec.get("RR") == RR and rec.get("Type") == "A":
            rid = rec["RecordId"]
            if rec.get("Value") == VALUE:
                print("exists", RR, VALUE, rid)
                return 0
            r = call(
                "UpdateDomainRecord",
                {"RecordId": rid, "RR": RR, "Type": "A", "Value": VALUE, "TTL": "600"},
            )
            print("updated", r)
            return 0 if "RequestId" in r else 1
    r = call(
        "AddDomainRecord",
        {"DomainName": DOMAIN, "RR": RR, "Type": "A", "Value": VALUE, "TTL": "600"},
    )
    print("added", r)
    return 0 if "RequestId" in r or "RecordId" in r else 1


if __name__ == "__main__":
    raise SystemExit(main())

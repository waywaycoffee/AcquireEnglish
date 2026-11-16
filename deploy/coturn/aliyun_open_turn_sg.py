#!/usr/bin/env python3
"""Noninteractive: open Aliyun SG for coturn (3478 + relay). Auto-confirm all."""
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

AK = os.environ.get("ALIYUN_ACCESS_KEY_ID", "").strip()
SK = os.environ.get("ALIYUN_ACCESS_KEY_SECRET", "").strip()
TARGET_IP = os.environ.get("ECS_PUBLIC_IP", "8.163.45.100")
REGIONS = [
    "cn-shenzhen",
    "cn-hangzhou",
    "cn-beijing",
    "cn-shanghai",
    "cn-guangzhou",
    "cn-hongkong",
    "ap-southeast-1",
]


def sign(params: dict, sk: str) -> str:
    qs = "&".join(
        f"{urllib.parse.quote(k, safe='')}={urllib.parse.quote(params[k], safe='')}"
        for k in sorted(params)
    )
    string_to_sign = "GET&%2F&" + urllib.parse.quote(qs, safe="")
    dig = hmac.new((sk + "&").encode(), string_to_sign.encode(), hashlib.sha1).digest()
    return base64.b64encode(dig).decode()


def call(action: str, extra: dict, region: str) -> dict:
    params = {
        "Format": "JSON",
        "Version": "2014-05-26",
        "AccessKeyId": AK,
        "SignatureMethod": "HMAC-SHA1",
        "Timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "SignatureVersion": "1.0",
        "SignatureNonce": str(uuid.uuid4()),
        "Action": action,
        "RegionId": region,
    }
    params.update(extra)
    params["Signature"] = sign(params, SK)
    url = "https://ecs.aliyuncs.com/?" + urllib.parse.urlencode(params)
    try:
        with urllib.request.urlopen(url, timeout=20) as r:
            return json.loads(r.read().decode())
    except Exception as e:  # noqa: BLE001
        if hasattr(e, "read"):
            return json.loads(e.read().decode())
        return {"error": str(e)}


def main() -> int:
    global AK, SK
    if not AK or not SK:
        print("missing AK/SK")
        return 2
    regions = list(REGIONS)
    rr = call("DescribeRegions", {}, "cn-hangzhou")
    for x in (rr.get("Regions") or {}).get("Region") or []:
        rid = x.get("RegionId")
        if rid and rid not in regions:
            regions.append(rid)
    print("scan_regions", len(regions))
    found = None
    for region in regions:
        r = call("DescribeInstances", {"PageSize": "50"}, region)
        instances = (r.get("Instances") or {}).get("Instance") or []
        if not instances:
            code = r.get("Code")
            if code and code not in {
                "InvalidOperation.NotSupportedEndpoint",
                "Forbidden.RAM",
            }:
                print(region, code, str(r.get("Message", ""))[:100])
            continue
        for inst in instances:
            pubs = (inst.get("PublicIpAddress") or {}).get("IpAddress") or []
            eip = ((inst.get("EipAddress") or {}).get("IpAddress") or "").strip()
            ips = list(pubs) + ([eip] if eip else [])
            print(region, inst.get("InstanceId"), inst.get("InstanceName"), ips)
            if TARGET_IP in ips or not TARGET_IP:
                sgs = (inst.get("SecurityGroupIds") or {}).get("SecurityGroupId") or []
                found = (region, inst.get("InstanceId"), sgs)
                if TARGET_IP in ips:
                    break
        if found and TARGET_IP:
            # keep searching until exact IP match preferred
            if any(True for _ in [1] if TARGET_IP):
                # re-check last printed
                pass
            # only stop early on exact IP
            exact = False
            for inst in instances:
                pubs = (inst.get("PublicIpAddress") or {}).get("IpAddress") or []
                eip = ((inst.get("EipAddress") or {}).get("IpAddress") or "").strip()
                ips = list(pubs) + ([eip] if eip else [])
                if TARGET_IP in ips:
                    sgs = (inst.get("SecurityGroupIds") or {}).get("SecurityGroupId") or []
                    found = (region, inst.get("InstanceId"), sgs)
                    exact = True
                    break
            if exact:
                break
    if not found:
        print("instance_not_found")
        return 1
    region, iid, sgs = found
    print("FOUND", region, iid, sgs)
    rules = [
        ("tcp", "3478/3478", "TURN TCP"),
        ("udp", "3478/3478", "TURN UDP"),
        ("udp", "49152/49200", "TURN relay UDP"),
    ]
    for sg in sgs:
        for proto, port, desc in rules:
            r = call(
                "AuthorizeSecurityGroup",
                {
                    "SecurityGroupId": sg,
                    "IpProtocol": proto,
                    "PortRange": port,
                    "SourceCidrIp": "0.0.0.0/0",
                    "Policy": "accept",
                    "Priority": "1",
                    "Description": desc,
                },
                region,
            )
            print(sg, proto, port, r.get("RequestId") or r.get("Code") or r)
    # verify
    Test = call(
        "DescribeSecurityGroupAttribute",
        {"SecurityGroupId": sgs[0], "Direction": "ingress"},
        region,
    )
    perms = (Test.get("Permissions") or {}).get("Permission") or []
    for p in perms:
        if "3478" in str(p.get("PortRange", "")) or "49152" in str(p.get("PortRange", "")):
            print("RULE", p.get("IpProtocol"), p.get("PortRange"), p.get("SourceCidrIp"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

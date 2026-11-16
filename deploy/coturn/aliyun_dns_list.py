#!/usr/bin/env python3
import hashlib, hmac, base64, json, os, time, uuid, urllib.parse, urllib.request
AK=os.environ["ALIYUN_ACCESS_KEY_ID"]; SK=os.environ["ALIYUN_ACCESS_KEY_SECRET"]
def sign(params, sk):
    qs="&".join(f"{urllib.parse.quote(k, safe='')}={urllib.parse.quote(params[k], safe='')}" for k in sorted(params))
    return base64.b64encode(hmac.new((sk+"&").encode(), ("GET&%2F&"+urllib.parse.quote(qs, safe="")).encode(), hashlib.sha1).digest()).decode()
def call(action, extra):
    params={"Format":"JSON","Version":"2015-01-09","AccessKeyId":AK,"SignatureMethod":"HMAC-SHA1","Timestamp":time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),"SignatureVersion":"1.0","SignatureNonce":str(uuid.uuid4()),"Action":action}
    params.update(extra); params["Signature"]=sign(params, SK)
    url="https://alidns.aliyuncs.com/?"+urllib.parse.urlencode(params)
    try: return json.loads(urllib.request.urlopen(url, timeout=20).read().decode())
    except Exception as e: return json.loads(e.read().decode()) if hasattr(e,"read") else {"error":str(e)}
print("DescribeDomainRecords", call("DescribeDomainRecords", {"DomainName":"curlhairai.com","PageSize":"50"}))

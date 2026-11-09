import urllib.request
import json
import ssl

BASE_URL = "https://129-146-110-196.sslip.io"
API_KEY = "aa0d07ca7079caf19492d0fc4a762c593b3e02e205c669ae60de5cbbd66979c2"

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

req = urllib.request.Request(f"{BASE_URL}/api/v1/bots", headers={
    "Content-Type": "application/json",
    "X-API-Key": API_KEY
})

with urllib.request.urlopen(req, context=ctx, timeout=15) as resp:
    data = json.loads(resp.read().decode('utf-8'))
    print("Type:", type(data))
    print("Dump:", json.dumps(data, indent=2))

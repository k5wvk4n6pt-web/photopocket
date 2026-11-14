#!/usr/bin/env python3
"""App Store Connect API で配布用証明書を一覧・後片付けする。

  list               → 今ある配布用証明書のIDを1行ずつ出力
  cleanup BEFORE.txt → BEFORE.txt に無い（＝このビルドで作った）配布用証明書を削除
"""
import json
import os
import sys
import time
import urllib.request

import jwt

ISSUER = os.environ["APP_STORE_CONNECT_ISSUER_ID"]
KEY_ID = os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"]
PRIVATE_KEY = os.environ["APP_STORE_CONNECT_PRIVATE_KEY"]
BASE = "https://api.appstoreconnect.apple.com"


def token():
    now = int(time.time())
    return jwt.encode(
        {"iss": ISSUER, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
        PRIVATE_KEY,
        algorithm="ES256",
        headers={"kid": KEY_ID, "typ": "JWT"},
    )


def call(method, path):
    req = urllib.request.Request(BASE + path, method=method, headers={"Authorization": "Bearer " + token()})
    with urllib.request.urlopen(req) as resp:
        body = resp.read()
        return json.loads(body) if body else None


def distribution_ids():
    data = call("GET", "/v1/certificates?filter[certificateType]=DISTRIBUTION,IOS_DISTRIBUTION&limit=200")
    return {c["id"] for c in data.get("data", [])}


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "list":
        for i in sorted(distribution_ids()):
            print(i)
    elif cmd == "cleanup":
        before = set(open(sys.argv[2]).read().split()) if os.path.exists(sys.argv[2]) else None
        if before is None:
            print("一覧ファイルが無いので後片付けをスキップします")
            sys.exit(0)
        for cid in sorted(distribution_ids() - before):
            print("このビルド用に作った一時的な証明書を削除:", cid)
            call("DELETE", "/v1/certificates/" + cid)

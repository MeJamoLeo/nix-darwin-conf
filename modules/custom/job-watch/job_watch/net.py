"""net — HTTP の薄い層。テストは http_get を差し替える（urllib を直接 patch しない）。"""
import json
import urllib.request
from . import config as C


def http_get(url, timeout=None):
    req = urllib.request.Request(url, headers={"User-Agent": C.USER_AGENT, "Accept": "application/json, text/html;q=0.9, */*;q=0.5"})
    with urllib.request.urlopen(req, timeout=timeout or C.FETCH_TIMEOUT) as r:
        return r.read().decode("utf-8", "replace")


def http_json(url, timeout=None):
    return json.loads(http_get(url, timeout))

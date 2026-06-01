import requests

from app.settings import Settings


def fetch(path):
    cfg = Settings()
    resp = requests.get(cfg.api_url + path, timeout=cfg.timeout)
    return resp.status_code

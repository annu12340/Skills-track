from app.settings import as_dict


def test_defaults():
    cfg = as_dict()
    assert cfg["timeout"] == 30
    assert cfg["api_url"].startswith("https://")

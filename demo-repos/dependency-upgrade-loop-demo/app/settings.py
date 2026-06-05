from pydantic import BaseSettings


class Settings(BaseSettings):
    api_url: str = "https://example.com/api"
    timeout: int = 30


def as_dict():
    return Settings().dict()

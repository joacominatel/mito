import re
from collections.abc import Iterable
from typing import Any

# A key matching any of these marks its whole value as identifying: every scalar under it is
# replaced. Matched case-insensitively against the full key. Extend here.
DENY_KEY_PATTERNS = (
    r".*puuids?",
    r".*(summoner|account|player|decliner|party|invitation|riot|game)ids?",
    r".*name",
    r".*tagline.*",
    r".*alias.*",
    r".*(chat|muc|conversation).*",
    r".*(jwt|token|password|secret|auth|encryption).*",
    r".*iconid",
    r"(?-i:ip|.*[a-z]Ip|.*IP|port|.*[a-z]Port)",
    r".*ipaddress",
)
# Keys that match a deny pattern but carry data the fixtures need.
ALLOW_KEYS = frozenset({"championName", "nameVisibilityType"})

_DENY = re.compile("|".join(f"(?:{p})" for p in DENY_KEY_PATTERNS), re.IGNORECASE)
_UUID = re.compile(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
_JWT = re.compile(r"eyJ[\w-]+\.[\w-]+\.[\w-]+")
_FAKE_UUID_PREFIX = "00000000-0000-4000-8000-"

# Shorter strings and smaller numbers are replaced where they are identifiers, but are not
# searched for inside other values: "Bob" or 29 would match unrelated data.
MIN_SEARCH_STRING = 5
MIN_SEARCH_INT = 100_000

REDACTED = "<redacted>"


class LeakError(Exception):
    """An identifier or secret survived anonymization. The message never contains it."""


def is_denied(key: str) -> bool:
    return key not in ALLOW_KEYS and _DENY.fullmatch(key) is not None


def _is_sentinel(value: Any) -> bool:
    return value is None or isinstance(value, bool) or value in (0, "")


def _digit_run(number: int) -> re.Pattern[str]:
    return re.compile(rf"(?<!\d){abs(number)}(?!\d)")


class Anonymizer:
    """Maps identifiers to fakes, consistently within one instance and never persisted.

    Feed every payload to `collect` first, then `apply` each one, then `verify` the output.
    """

    def __init__(self, secrets: Iterable[str] = (), port: int | None = None) -> None:
        self._secrets = [s for s in secrets if s]
        self._port = _digit_run(port) if port else None
        self._strings: dict[str, str] = {}
        self._ints: dict[int, int] = {}
        self._fakes: set[str] = set()
        self._search_cache: tuple[Any, re.Pattern[str] | None, dict[str, str]] = (None, None, {})

    def collect(self, value: Any, denied: bool = False) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                self._collect_shaped(key)
                self.collect(child, denied or is_denied(key))
        elif isinstance(value, list):
            for child in value:
                self.collect(child, denied)
        elif isinstance(value, str):
            self._collect_shaped(value)
            if denied and value:
                self._fake_string(value)
        elif denied and not _is_sentinel(value) and isinstance(value, int | float):
            self._fake_int(int(value))

    def apply(self, value: Any, denied: bool = False) -> Any:
        if isinstance(value, dict):
            return {
                self._scrub_string(key): self.apply(child, denied or is_denied(key))
                for key, child in value.items()
            }
        if isinstance(value, list):
            return [self.apply(child, denied) for child in value]
        if isinstance(value, str):
            if denied and value:
                return self._lookup(self._strings, value)
            return self._scrub_string(value)
        if _is_sentinel(value) or not isinstance(value, int | float):
            return value
        number = int(value)
        if denied or (abs(number) >= MIN_SEARCH_INT and number in self._ints):
            fake = self._lookup(self._ints, number)
            return float(fake) if isinstance(value, float) else fake
        return value

    @staticmethod
    def _lookup[K, V](mapping: dict[K, V], raw: K) -> V:
        if raw not in mapping:
            raise LeakError("apply() met an identifier that collect() never saw")
        return mapping[raw]

    def verify(self, value: Any) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                self._verify_string(key)
                self.verify(child)
        elif isinstance(value, list):
            for child in value:
                self.verify(child)
        elif isinstance(value, str):
            self._verify_string(value)
        elif (
            not _is_sentinel(value)
            and isinstance(value, int | float)
            and abs(int(value)) >= MIN_SEARCH_INT
            and int(value) in self._ints
        ):
            raise LeakError("a collected numeric identifier survived anonymization")

    def verify_text(self, text: str) -> None:
        if any(secret in text for secret in self._secrets):
            raise LeakError("the auth token appears in the output")

    def _collect_shaped(self, text: str) -> None:
        for match in (*_UUID.findall(text), *_JWT.findall(text)):
            if not match.startswith(_FAKE_UUID_PREFIX):
                self._fake_string(match)

    def _fake_string(self, raw: str) -> str:
        if raw not in self._strings:
            n = len(self._strings) + 1
            fake = f"{_FAKE_UUID_PREFIX}{n:012d}" if _UUID.fullmatch(raw) else f"anon-{n}"
            self._strings[raw] = fake
            self._fakes.add(fake)
        return self._strings[raw]

    def _fake_int(self, raw: int) -> None:
        self._ints.setdefault(raw, len(self._ints) + 1)

    def _search(self) -> tuple[re.Pattern[str] | None, dict[str, str]]:
        """One pattern for every collected value long enough to look for inside text."""
        key = (len(self._strings), len(self._ints))
        if self._search_cache[0] != key:
            found = {
                raw: fake for raw, fake in self._strings.items() if len(raw) >= MIN_SEARCH_STRING
            }
            numbers = {
                str(abs(raw)): str(fake)
                for raw, fake in self._ints.items()
                if abs(raw) >= MIN_SEARCH_INT
            }
            parts = [re.escape(raw) for raw in sorted(found, key=len, reverse=True)]
            parts += [rf"(?<!\d){digits}(?!\d)" for digits in numbers]
            pattern = re.compile("|".join(parts)) if parts else None
            self._search_cache = (key, pattern, found | numbers)
        return self._search_cache[1], self._search_cache[2]

    def _scrub_string(self, text: str) -> str:
        if text in self._fakes:
            return text
        if text in self._strings:
            return self._strings[text]
        for secret in self._secrets:
            text = text.replace(secret, REDACTED)
        if self._port:
            text = self._port.sub(REDACTED, text)
        pattern, fakes = self._search()
        return pattern.sub(lambda match: fakes[match.group()], text) if pattern else text

    def _verify_string(self, text: str) -> None:
        if any(secret in text for secret in self._secrets):
            raise LeakError("the auth token appears in the output")
        if self._port and self._port.search(text):
            raise LeakError("the client port appears in the output")
        if text in self._strings and text not in self._fakes:
            raise LeakError("a collected identifier survived anonymization")
        pattern, _ = self._search()
        if pattern and pattern.search(text):
            raise LeakError("a collected identifier survived anonymization")
        for match in _UUID.findall(text):
            if not match.startswith(_FAKE_UUID_PREFIX):
                raise LeakError("an unmapped UUID-shaped value appears in the output")
        if _JWT.search(text):
            raise LeakError("a JWT-shaped value appears in the output")

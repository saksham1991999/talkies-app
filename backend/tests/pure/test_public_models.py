"""What another person can receive must hold no diary date or diary field.

The rule (backend/API.md, Phase 2): no response to another person holds a diary
date, `created`, `memo`, `place`, `seat`, `price`, `with`, `tags`, `no`,
`planned`, or `added`. `stats` has no per-month or per-year numbers.
"""

import re
import typing
from datetime import date, datetime

from pydantic import BaseModel

from app.schemas import phase2, phase3, phase4, phase5
from app.schemas.common import Base

DIARY_FIELDS = {
    "created",
    "memo",
    "place",
    "seat",
    "price",
    "with",
    "tags",
    "no",
    "planned",
    "added",
    "date",
    "watched_on",
    "watched_at",
    "viewed_at",
    "updated_at",
    "deleted_at",
    "month",
    "year",
    "months",
    "years",
    "per_month",
    "per_year",
}
DATE_LIKE = re.compile(r"(_at|_on|_date|_time|_day|date|time)$")

# Group features have their own times (a night starts, a message was sent). They are the
# group's, not a diary date. `place` on a night is where the group meets.
GROUP_TIMES = {"starts_at", "created_at"}
GROUP_OK = {
    ("Night", "place"),
    ("NightEvent", "place"),
    ("NightCreate", "place"),
    ("ClosePost", "place"),
    ("WrapupResult", "created"),  # a count of stubs, not a date
}


def models_of(module) -> list[type[BaseModel]]:
    return [
        cls
        for cls in vars(module).values()
        if isinstance(cls, type) and issubclass(cls, Base) and cls.__module__ == module.__name__
    ]


def date_types(annotation) -> bool:
    if annotation in (datetime, date):
        return True
    if isinstance(annotation, type) and issubclass(annotation, BaseModel):
        return any(date_types(f.annotation) for f in annotation.model_fields.values())
    return any(date_types(arg) for arg in typing.get_args(annotation))


def walk(schema, found: list[str]) -> None:
    """Collect the `format: date*` entries of a JSON schema."""
    if isinstance(schema, dict):
        if schema.get("format") in {"date", "date-time", "time"}:
            found.append(schema["format"])
        for value in schema.values():
            walk(value, found)
    elif isinstance(schema, list):
        for value in schema:
            walk(value, found)


def test_phase_2_models_have_no_date_field_name_or_type():
    models = models_of(phase2)
    assert len(models) > 15
    for cls in models:
        for name, field in cls.model_fields.items():
            assert name not in DIARY_FIELDS, (cls.__name__, name)
            assert not DATE_LIKE.search(name), (cls.__name__, name)
            assert not date_types(field.annotation), (cls.__name__, name)
        formats: list[str] = []
        walk(cls.model_json_schema(), formats)
        assert formats == [], cls.__name__


def test_group_models_hold_no_diary_field():
    for module in (phase3, phase4, phase5):
        for cls in models_of(module):
            for name in cls.model_fields:
                if (cls.__name__, name) in GROUP_OK:
                    continue
                assert name not in DIARY_FIELDS - GROUP_TIMES, (cls.__name__, name)
                if DATE_LIKE.search(name):
                    assert name in GROUP_TIMES, (cls.__name__, name)


def test_group_times_are_only_where_the_group_needs_them():
    users_of_times = {
        (cls.__name__, name)
        for module in (phase3, phase4, phase5)
        for cls in models_of(module)
        for name, field in cls.model_fields.items()
        if date_types(field.annotation)
    }
    assert users_of_times == {
        ("NightOption", "starts_at"),
        ("NightEvent", "starts_at"),
        ("NightCreate", "slots"),
        ("Night", "options"),
        ("Night", "event"),
        ("NightList", "items"),
        ("Message", "created_at"),
        ("MessageList", "items"),
    }


def test_stats_have_no_per_month_or_per_year_numbers():
    assert set(phase2.Stats.model_fields) == {
        "films",
        "viewings",
        "avg_rating",
        "top_genres",
        "top_langs",
    }

"""backend/API.md, the Pydantic models, and tests/examples must agree.

The Flutter tests parse the same example files with the client models.
"""

import json
import re
from pathlib import Path

import pytest

from app.schemas import MODELS

BACKEND = Path(__file__).resolve().parents[2]
API = BACKEND / "API.md"
EXAMPLES = BACKEND / "tests" / "examples"
SPARSE = {"me_patch"}  # "any of": a request may leave fields out

KANTARA = {
    "id": "Q949228",
    "t": "Kantara",
    "y": 2022,
    "d": "2022-09-30",
    "g": ["action", "drama"],
    "l": ["kn"],
    "c": ["IN"],
    "dir": ["Rishab Shetty"],
    "cast": ["Rishab Shetty", "Sapthami Gowda"],
    "p": "en/a/a5/Kantara_film_poster.jpg",
    "pop": 61,
}


def api_model_names() -> list[str]:
    """The names in the "Models" code block of API.md."""
    text = API.read_text()
    block = re.search(r"## Models.*?```\n(.*?)```", text, re.S)
    assert block, "API.md has no Models block"
    names = []
    for line in block.group(1).splitlines():
        found = re.match(r"^([a-z][a-z_]*)\s{2,}\S", line)
        if found:
            names.append(found.group(1))
    return names


def example_files() -> list[Path]:
    return sorted(EXAMPLES.glob("*.json"))


def camel(name: str) -> str:
    return "".join(part.capitalize() for part in name.split("_"))


def test_api_md_lists_the_models_the_code_has():
    names = api_model_names()
    assert len(names) == len(set(names)), "a model is listed twice in API.md"
    assert set(names) == set(MODELS)


def test_class_name_is_camel_case_of_the_model_name():
    for name, cls in MODELS.items():
        assert cls.__name__ == camel(name), name


def test_every_model_has_an_example_and_every_example_a_model():
    have = {path.name.split(".")[0] for path in example_files()}
    assert have == set(MODELS)
    for path in example_files():
        assert re.fullmatch(r"[a-z_]+\.[a-z_]+\.json", path.name), path.name


@pytest.mark.parametrize("path", example_files(), ids=lambda p: p.name)
def test_example_parses_and_round_trips(path: Path):
    model = MODELS[path.name.split(".")[0]]
    text = path.read_text()
    wire = json.loads(text)
    parsed = model.model_validate_json(text)
    if model.__name__ == "MePatch":
        again = parsed.model_dump(mode="json", exclude_unset=True)
    else:
        # Every key is present, nulls are explicit: the full dump equals the file.
        again = parsed.model_dump(mode="json")
    assert again == wire
    assert json.loads(parsed.model_dump_json(exclude_unset=model.__name__ == "MePatch")) == wire


@pytest.mark.parametrize("path", example_files(), ids=lambda p: p.name)
def test_example_uses_the_shared_film_snapshot(path: Path):
    def films(value, key=None):
        if isinstance(value, dict):
            if key == "film" and "t" in value:
                yield value
            for k, v in value.items():
                yield from films(v, k)
        elif isinstance(value, list):
            for item in value:
                yield from films(item, key)

    for film in films(json.loads(path.read_text())):
        assert film == KANTARA


def test_examples_follow_the_text_rules():
    for path in example_files():
        text = path.read_text()
        assert chr(0x2014) not in text and chr(0x2013) not in text, path.name
        assert text.endswith("}\n"), path.name


def test_a_request_with_an_unknown_key_is_refused():
    for name, cls in MODELS.items():
        if name in {"error"}:
            continue
        for path in EXAMPLES.glob(f"{name}.*.json"):
            wire = json.loads(path.read_text())
            wire["surprise"] = 1
            with pytest.raises(ValueError):
                cls.model_validate(wire)
            break


def test_times_in_examples_are_utc_with_milliseconds():
    pattern = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$")
    fields = {"updated_at", "server_time", "starts_at", "created_at"}

    def check(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key == "data":
                    continue  # the phone's own JSON keeps its own date formats
                if key in fields and item is not None:
                    assert pattern.match(item), (key, item)
                check(item)
        elif isinstance(value, list):
            for item in value:
                check(item)

    for path in example_files():
        check(json.loads(path.read_text()))

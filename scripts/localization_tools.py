"""Text-only course overlay format shared by authoring and verification tools."""
import hashlib


def digest(data):
    return hashlib.sha256(data).hexdigest()


def value_key(entity_id, field, value):
    return f"{entity_id}.{field}.{digest(value.encode('utf-8'))}"


def entities(course):
    yield course, ("title", "summary")
    for section in course["sections"]:
        yield section, ("title", "summary")
        for lesson in section["lessons"]:
            yield lesson, ("title", "summary", "theory", "microscope", "recap")
            for exercise in lesson["exercises"]:
                yield exercise, ("title", "prompt", "explanation")


def source_texts(course):
    texts = {}
    for entity, fields in entities(course):
        entity_id = entity["id"]
        for field in fields:
            texts[f"{entity_id}.{field}"] = entity[field]
        for level, hint in enumerate(entity.get("hints", []), 1):
            texts[f"{entity_id}.hint.{level}"] = hint
        for field, values in [("choice", entity.get("choices", [])), ("skill", entity.get("skills", []))]:
            for value in values:
                texts[value_key(entity_id, field, value)] = value
    return texts

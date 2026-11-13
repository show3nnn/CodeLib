"""Text-only English authoring helpers. No code, fixtures or grading values are generated."""
OUTPUT_PROMPT = "Predict the program's exact output. Preserve spaces and line breaks."


def lesson(title, summary, theory, microscope, recap):
    return dict(title=title, summary=summary, theory=theory, microscope=microscope, recap=recap)


def task(title, prompt, hints, explanation, choices=None):
    result = dict(title=title, prompt=prompt, hints=hints, explanation=explanation)
    if choices is not None:
        result["choices"] = choices
    return result


def output(title, hints, explanation):
    return task(title, OUTPUT_PROMPT, hints, explanation)

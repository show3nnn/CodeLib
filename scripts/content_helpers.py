"""Authoring helpers only. The application reads the committed JSON, never Python."""
def program(body, headers="iostream"):
    return "".join(f"#include <{h}>\n" for h in headers.split()) + "\nint main() {\n" + "\n".join("    " + line for line in body.splitlines()) + "\n}\n"

def code(key, title, prompt, body, cases, hints, explanation, headers="iostream", difficulty=1):
    return dict(id=key, title=title, kind="code", prompt=prompt,
                starter=program("// Напишите решение здесь", headers),
                solution=program(body, headers), answer=None, choices=[], hints=hints,
                explanation=explanation, difficulty=difficulty, skills=[],
                testCases=[case if isinstance(case, dict) else dict(input=case[0], output=case[1]) for case in cases])

def output(key, title, body, expected, hints, explanation, headers="iostream"):
    source = program(body, headers)
    return dict(id=key, title=title, kind="output", prompt="Предскажите точный вывод программы. Сохраните пробелы и переносы строк.",
                starter=source, solution=source, answer=expected, choices=[], hints=hints,
                explanation=explanation, difficulty=1, skills=[], testCases=[dict(input="", output=expected)])

def choice(key, title, prompt, choices, correct, hints, explanation):
    return dict(id=key, title=title, kind="choice", prompt=prompt, starter="", solution="",
                answer=choices[correct], choices=choices, hints=hints, explanation=explanation,
                difficulty=1, skills=[], testCases=[])

def lesson(key, title, summary, theory, example, microscope, recap, exercises, skills):
    for task in exercises:
        task["id"] = f"cpp.{key}.{task['id']}"
        task["skills"] = skills
    return dict(id=f"cpp.{key}", title=title, summary=summary, minutes=20,
                prerequisites=[], theory=theory, example=example, microscope=microscope,
                recap=recap, exercises=exercises)

def section(key, title, summary, lessons):
    return dict(id=f"cpp.section.{key}", title=title, summary=summary, lessons=lessons)

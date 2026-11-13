"""Reviewed-by-author draft of lesson cpp.first; NOT an available app language.

The source snapshot is intentional: update it only after reviewing course changes.
Code, expected output and grading values are not translated.
"""
SOURCE_SHA256 = "435ec03a6945a041d489ee395b326d3eeda7966c7e6e31b111b068fdc663ca0e"

ENTITIES = {
    "cpp-foundations": {
        "title": "C++ — from your first program to first-year confidence",
        "summary": "A hands-on C++17 course: from your first program to containers, memory, objects and console projects. Reference solutions are also checked in C++20.",
    },
    "cpp.section.start": {
        "title": "1. Your first programs",
        "summary": "From source code to your own status board.",
    },
    "cpp.first": {
        "title": "Programs and main",
        "summary": "Give the computer its first precise instruction.",
        "theory": 'An algorithm is a finite sequence of steps that an executor can follow. A program expresses an algorithm in a programming language. C++ is case-sensitive: main and Main are different names.\n\nAn ordinary console program starts executing in int main(). Braces enclose its body. The statement std::cout << "Ready"; sends text to standard output. A semicolon ends the statement; quotation marks delimit the text and are not printed. The directive #include <iostream> makes input/output declarations available. For now, use this structure without trying to memorize every detail.\n\nIn codelib, you can write code, save it and compare it with a reference solution. There is no built-in execution yet. Do not confuse marking a task complete yourself with checking a program using a compiler.',
        "microscope": "A compiler translates C++ source into object code and reports violations of the language rules. A linker combines object files and the required libraries into an executable. Compilation does not prove that an algorithm is correct: a program can compile successfully and still produce the wrong result. Reaching the end of int main() is equivalent to return 0; — this is a special rule for main, not for every function.",
        "recap": "Check the name main, matching braces, quotation marks and the semicolon. The output is not the text of the entire program.",
    },
    "cpp.first.beacon": {
        "title": "Station beacon",
        "prompt": "Write a complete program that takes no input and prints exactly Beacon online (without quotation marks).",
        "hints": ["One output statement is enough.", "Put the message in double quotation marks after std::cout <<."],
        "explanation": "The message is a string literal. The space inside the quotation marks is part of the output.",
    },
    "cpp.first.read": {
        "title": "What will the operator see?",
        "prompt": "Predict the program's exact output. Preserve spaces and line breaks.",
        "hints": ["The quotation marks are not printed.", "The space inside the string is preserved."],
        "explanation": "The contents of the literal are printed: Dock 7.",
    },
    "cpp.first.repair": {
        "title": "The missing semicolon",
        "prompt": 'Fix this program: int main() { std::cout << "Signal" } . Add the required include directive. The output must be Signal.',
        "hints": ["Every output statement needs a terminating symbol.", "Add ; after the literal and include iostream."],
        "explanation": "The semicolon terminates the statement, while the closing brace ends the body of main.",
    },
    "cpp.first.compiler": {
        "title": "If it compiles, is it correct?",
        "prompt": "A program compiles successfully but prints 0 instead of a ticket price. What has compilation established?",
        "choices": {
            "Все требования задачи выполнены": "All task requirements have been met",
            "Исходный текст прошёл проверки компилятора, но алгоритм ещё нужно проверить": "The source passed the compiler's checks, but the algorithm still needs testing",
            "Программа никогда не завершится с ошибкой": "The program can never fail at runtime",
        },
        "hints": ["The compiler does not know the ticket price required by the task.", "Language rules and task requirements are different levels of checking."],
        "explanation": "Correct syntax does not guarantee a correct result or the absence of runtime errors.",
    },
    "cpp.first.signature": {
        "title": "Your own callsign",
        "prompt": "Try a callsign of your own in the draft, then print exactly Pilot: Vega for the checkable version. There is no input.",
        "hints": ["The colon is an ordinary text character.", "You can print the entire message using a single string literal."],
        "explanation": "In this first task, you can experiment in your draft; the exact required format gives you an unambiguous result to check.",
    },
}

SKILLS = {"main": "main", "cout": "cout", "компиляция": "compilation"}

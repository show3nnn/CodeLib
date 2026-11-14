"""English draft of section 1; NOT an available app language.

The source snapshot is intentional: update it only after reviewing course changes.
Code, expected output and grading values are not translated.
"""
SOURCE_SHA256 = "1ba8f26578c0c5bc70e03c4f4b470b30198969b5ba08d321b304f99f5c99c349"
SECTION_ID = "cpp.section.start"

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
        "theory": 'An algorithm is a finite sequence of steps that an executor can follow. A program expresses an algorithm in a programming language. C++ is case-sensitive: main and Main are different names.\n\nAn ordinary console program starts executing in int main(). Braces enclose its body. The statement std::cout << "Ready"; sends text to standard output. A semicolon ends the statement; quotation marks delimit the text and are not printed. The directive #include <iostream> makes input/output declarations available. For now, use this structure without trying to memorize every detail.\n\nIn codelib, you can write code, save it and run it right in the editor: the program executes in a separate disposable environment. A successful run shows output but never completes the task by itself: it needs checking against the condition\u2019s examples or your own mark.',
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

ENTITIES.update({
    "cpp.lines": {
        "title": "Lines and sequence",
        "summary": "Build a multiline message from individual statements.",
        "theory": 'Statements execute in order, from top to bottom. Separate output operations join their text without adding spaces. To start a new line, put \\n inside a string literal. For example, "A\\nB" contains A, a line break and B. You can write std::cout << "A" << "B"; as one output chain.\n\nSpaces and line breaks in the source file outside quotation marks usually format the code and are not printed. A line break in the output appears only when explicitly requested. These tasks show the required output; a final line break is acceptable when comparing results by hand, but an extra blank line changes the output.',
        "microscope": "\\n is an escape sequence representing a newline character, not two printed characters. std::endl also ends the line but additionally flushes the stream buffer; \\n is sufficient for ordinary messages in these exercises.",
        "recap": "Without an explicit separator, messages run together. Sketch the intended output lines first, then add the line breaks.",
    },
    "cpp.lines.manifest": {
        "title": "Cargo manifest", "prompt": "Print three lines: Cargo, then Food, then Tools. Do not add blank lines.",
        "hints": ["You need two line separators.", "Put \\n between the names."],
        "explanation": "Two line breaks separate three lines without creating a blank line between them.",
    },
    "cpp.lines.joined": {
        "title": "Joined channels", "prompt": "Predict the program's exact output. Preserve spaces and line breaks.",
        "hints": ["A new statement does not mean a new output line.", "The only space is before the digit 2."],
        "explanation": "Air and lock join directly; the space comes only from the final literal.",
    },
    "cpp.lines.bridge": {
        "title": "Repair the display", "prompt": "The display prints DockReady with no separator. Write a program that prints Dock and Ready on separate lines.",
        "hints": ["You need a separator between the words.", "Use \\n, not a space."],
        "explanation": "The line break separates the two states without changing the words themselves.",
    },
    "cpp.lines.source": {
        "title": "Source-code whitespace", "prompt": 'Will the output of std::cout << "A"; change if you indent the statement on the next line of the source file?',
        "choices": {"Да, появится отступ": "Yes, indentation will appear", "Нет, пробелы вне литерала не выводятся": "No, spaces outside the literal are not printed", "Да, появится пустая строка": "Yes, a blank line will appear"},
        "hints": ["The characters inside quotation marks matter.", "Source formatting and program output are different things."],
        "explanation": "Indentation makes source code easier to read; it is not an output command.",
    },
    "cpp.lines.countdown": {
        "title": "A countdown without loops", "prompt": "Without using loops yet, print the lines 3, 2, 1, Go! in exactly that order.",
        "hints": ["There are four lines in total.", "Use three line breaks inside the literal."],
        "explanation": "The text order follows the execution order. We will study loops later.",
    },
    "cpp.escapes": {
        "title": "Quotes, backslashes and comments", "summary": "Print characters that have special meaning in C++.",
        "theory": 'Inside a string literal, a double quotation mark ends the text. To print the quotation mark itself, write \\". To print a backslash, write \\\\. The sequence \\t represents a tab, but its visual width depends on where it is displayed; these tasks use ordinary spaces for exact alignment.\n\nA // comment continues to the end of the source line and is not executed. A /* ... */ comment can span several lines. Inside quotation marks, // is just text. Do not hide the only required statements inside a comment.',
        "microscope": "The compiler interprets escape sequences when processing literals. The length of the source spelling can therefore differ from the number of output characters. Do not use unknown sequences such as \\L: they are not a reliable way to print a backslash.",
        "recap": 'Use \\" to print a quotation mark and \\\\ to print a backslash. Comments outside strings do not produce output.',
    },
    "cpp.escapes.quote": {
        "title": "A quotation from the robot", "prompt": 'Print exactly Robot: "Hello", including the double quotation marks around Hello.',
        "hints": ["The outer quotation marks delimit the literal.", "Escape the quotation marks inside it using backslashes."],
        "explanation": "Escaped quotation marks belong to the text instead of ending the literal.",
    },
    "cpp.escapes.comment": {
        "title": "Comment or message?", "prompt": "Predict the program's exact output. Preserve spaces and line breaks.",
        "hints": ["Look at what is inside the quotation marks.", "The comment starts only after the closing quotation mark and semicolon."],
        "explanation": "Inside a string literal, // does not start a comment.",
    },
    "cpp.escapes.path": {
        "title": "Path to the archive", "prompt": "Print exactly C:\\Lab\\notes.txt. This is a practice string, not a file operation.",
        "hints": ["Double every backslash in the literal.", "Pay particular attention to \\n: without doubling the backslash, it represents a newline."],
        "explanation": "\\\\ becomes one backslash. The program does not open any files.",
    },
    "cpp.escapes.literal": {
        "title": "Two characters, not a newline", "prompt": "Which spelling inside a literal prints two characters: a backslash followed by the letter n?",
        "choices": {r"\n": r"\n", r"\\n": r"\\n", r"/n": r"/n"},
        "hints": ["First produce an ordinary backslash.", "Doubling the backslash removes its escape role for the following n."],
        "explanation": "In \\\\n, the first two backslashes produce one backslash, followed by the printed n.",
    },
    "cpp.escapes.label": {
        "title": "A label without magic", "prompt": 'Print two lines: "Sample" (including quotation marks), then // checked. Do not use tabs.',
        "hints": ["The first line has two escaped quotation marks.", "Follow it with \\n and keep // inside the literal."],
        "explanation": "A string can contain characters that look like C++ syntax. Inside the literal, they are data.",
    },
    "cpp.board": {
        "title": "Mini-project: status board", "summary": "Assemble and check a complete text message.",
        "theory": "This mini-project combines the program structure, exact output and special characters. Write down the required result first, then identify the line breaks, quotation marks and backslashes. Write the program and compare it with the reference solution. There is no input: the board is static for now.\n\nBefore marking the task, check every line: letter case, spaces and punctuation. You can run the program with \u201cRun\u201d and compare the output with the condition; running alone never completes the task. Editing a draft does not erase an earlier completion mark: the status means that you completed the task previously, not that the current source has been checked again.",
        "microscope": "Program output and a source file are different representations. Compare the result with the requirements, not the appearance of your code with the reference: different programs can print the same text. Comparing source text is therefore not a correct way to judge solutions.",
        "recap": "Requirements first, then code, then compare the result. Do not call a program automatically checked when you have only read the reference solution.",
    },
    "cpp.board.panel": {
        "title": "Station panel", "prompt": 'Create a board with three lines: == STATUS ==, Unit: "Orion", Ready. The second line includes quotation marks.',
        "hints": ["Mark the two line boundaries first.", "The quotation marks around Orion need escaping."],
        "explanation": "One literal and several output statements are equally valid approaches when they produce the same required result.",
    },
    "cpp.board.spacing": {
        "title": "Space inspection", "prompt": "Predict the program's exact output. Preserve spaces and line breaks.",
        "hints": ["There are no spaces inside the first pair of brackets.", "On the second line, B has a space on each side."],
        "explanation": "The << chain does not insert spaces by itself.",
    },
    "cpp.board.card": {
        "title": "Expedition card", "prompt": 'Print four lines: Mission 1, Crew: 2, Path: C:\\Orbit, "Launch". For now, you may write the digits directly inside the text.',
        "hints": ["Do not confuse the path with an escape sequence.", 'Combine \\\\ for the path, \\n for lines and \\" for quotation marks.'],
        "explanation": "The digits inside quotation marks are text here; there is no arithmetic yet.",
    },
    "cpp.board.review": {
        "title": "How should solutions be compared?", "prompt": "The reference uses one std::cout statement, while you use three. The output is identical. Is that necessarily an error?",
        "choices": {"Да, число инструкций должно совпадать": "Yes, the number of statements must match", "Нет, важен требуемый результат, если условие не ограничивает способ": "No, the required result matters unless the task restricts the method", "Да, три инструкции всегда медленнее в три раза": "Yes, three statements are always three times slower"},
        "hints": ["The task does not restrict the number of statements.", "More than one implementation can be correct."],
        "explanation": "Comparing source text would reject valid alternatives. Check behavior and the task's constraints instead.",
    },
    "cpp.board.repair": {
        "title": "The board's final check", "prompt": "A friend mixed up the lines. Restore the protocol: OPEN first, then one blank line, then CLOSE.",
        "hints": ["There must be a separate empty line between the text lines.", "Two consecutive line breaks produce one blank line."],
        "explanation": "The first line break ends OPEN; the second ends the empty line.",
    },
})

SKILLS = {"main": "main", "cout": "cout", "компиляция": "compilation", "последовательность": "sequence", "переносы": "line breaks", "escape": "escape sequences", "комментарии": "comments", "точный вывод": "exact output", "самопроверка": "self-review"}

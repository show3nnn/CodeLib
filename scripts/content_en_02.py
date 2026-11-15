"""English draft of the full data/input section; not an available app language."""
SOURCE_SHA256 = "3e64532482e4897d937021bdd71f710144bd38f8bb58f7cc77cf708bd811ecac"
SECTION_ID = "cpp.section.data"

ENTITIES = {
    "cpp.section.data": {"title": "2. Data and input", "summary": "Teach your program to respond to input."},
    "cpp.input": {
        "title": "int and std::cin", "summary": "Read numbers and use them in calculations.",
        "theory": 'A variable is a named object that stores a value of a particular type. int count = 0; creates an integer variable named count with the initial value 0. Names are case-sensitive. std::cin >> count; reads an integer from standard input and stores it in count. You can read several numbers in a chain: std::cin >> price >> count;. Spaces and line breaks separate the numbers.\n\nDo not use quotation marks when printing a variable: std::cout << count;. Writing "count" would print the word. The operators + and * add and multiply numbers. In this section, input is guaranteed to be valid and all results fit in int; we will study invalid input later. Do not print prompts such as "Enter a number" when the required output contains only the answer.',
        "microscope": "int has a finite range. The C++ standard guarantees at least 16 bits, not exactly 32 bits on every system. These introductory tasks use small values. Initializing a variable to zero does not replace input validation, but it prevents accidental use of an uninitialized value before input.",
        "recap": "Declare the variables, read them using >>, calculate the result and print it using <<.",
    },
    "cpp.input.cargo": {
        "title": "Cargo in two compartments", "prompt": "Input: two integers a and b from 0 to 100. Print their sum, the total cargo.",
        "hints": ["Each compartment needs a variable.", "After reading the values, print a + b."],
        "explanation": "The input chain accepts either spaces or line breaks between the numbers.",
    },
    "cpp.input.literal": {
        "title": "Name and value", "prompt": "Predict the program's exact output. Preserve spaces and line breaks.",
        "hints": ["The first count is inside quotation marks.", "The second count refers to the variable's value."],
        "explanation": "The literal prints the word; referring to the variable prints its stored number.",
    },
    "cpp.input.fuel": {
        "title": "Fuel for the trips", "prompt": "Input: fuel per trip f (0–100) and number of trips n (0–100). Print the total fuel consumption.",
        "hints": ["The same consumption repeats n times.", "Use multiplication: f * n."],
        "explanation": "Do not print units: the required format contains only a number.",
    },
    "cpp.input.read": {
        "title": "Which way does the arrow point?", "prompt": "Which statement reads a number into an already declared variable n?",
        "choices": {"std::cout << n;": "std::cout << n;", "std::cin >> n;": "std::cin >> n;", 'std::cin >> "n";': 'std::cin >> "n";'},
        "hints": ["Use cin for input.", "Input must store a value in an object, not in a string literal."],
        "explanation": "std::cin >> n reads into n; std::cout << n prints the value of n.",
    },
    "cpp.input.reverse": {
        "title": "Reverse the report order", "prompt": "Input: two dock numbers a and b (1–99). Print b first, then a, separated by one space.",
        "hints": ["Read the numbers in their original order.", 'Start the output chain with b and insert " ".'],
        "explanation": "Variables let you use data in a different order from the order in which it arrived.",
    },
    "cpp.assignment": {
        "title": "Assignment and state", "summary": "Trace how a program changes its values.",
        "theory": "int energy = 20; creates an object with an initial value. energy = 12; changes an existing object. Assignment evaluates the right-hand side first, then stores the result on the left: energy = energy + 5; adds 5 to the previous value. It is not a mathematical equality.\n\nThe shorthand energy += 5; does the same for our integer variable. The operators -= and *= work similarly. After assignment, the old value is lost unless you saved it elsewhere. To exchange values, use a temporary variable: int saved = a; a = b; b = saved;. Names must start with a letter or underscore; for these exercises, choose clear Latin-letter names and avoid reserved naming patterns.",
        "microscope": "The right-hand side uses the state before the result is stored. In a = b;, the value of b is copied; no lasting connection is created between the variables. Changing b afterwards does not change a. References, which can provide another name for an object, will appear in a separate section.",
        "recap": "Write down the value after each statement. Do not read an assignment as an equation.",
    },
    "cpp.assignment.battery": {
        "title": "Drone battery", "prompt": "Input: initial charge e (0–100), added charge add (0–100), and consumption used (0–100), with used ≤ e + add. Update e and print the remaining charge.",
        "hints": ["Add the charge first, then subtract the consumption.", "Use e += add and e -= used."],
        "explanation": "The changes happen in sequence; e stores the current charge.",
    },
    "cpp.assignment.copy": {
        "title": "A copy is not a connection", "prompt": "Predict the program's exact output. Preserve spaces and line breaks.",
        "hints": ["b received its value when it was initialized.", "Changing a afterwards does not change b."],
        "explanation": "Copying an int gives the other object an independent value.",
    },
    "cpp.assignment.swap": {
        "title": "Swap the containers", "prompt": "Input: two integers a and b from −100 to 100. Exchange their values using a third variable, then print the new a and b separated by a space.",
        "hints": ["Otherwise, the first assignment would destroy one of the values.", "Save a first, then overwrite a and restore b from saved."],
        "explanation": "Printing b a without swapping would produce the same text, but it would not satisfy the requirement to change the variables.",
    },
    "cpp.assignment.equal": {
        "title": "Not an equation", "prompt": "For int x = 5;, what does x = x + 1; do?",
        "choices": {"Утверждает невозможное равенство": "Asserts an impossible equality", "Сохраняет 6 в x": "Stores 6 in x", "Сравнивает x с 6": "Compares x with 6"},
        "hints": ["Evaluate the right-hand side first.", "The = sign stores the result in the left-hand variable."],
        "explanation": "Equality comparison in C++ uses ==, not =.",
    },
    "cpp.assignment.inventory": {
        "title": "Stock after two trips", "prompt": "Input: boxes (0–100), taken (0–boxes), arrived (0–100). First taken boxes leave the warehouse, then arrived boxes come in. Print the original and new counts separated by a space.",
        "hints": ["Keep the original count for the report.", "Copy boxes into before prior to changing it."],
        "explanation": "State history is not kept automatically; explicitly save any earlier value that you need.",
    },
    "cpp.types": {
        "title": "double, char and bool", "summary": "Choose a type that fits the meaning of your data.",
        "theory": 'double stores numbers with a fractional part: double distance = 2.5;. In C++ source, use a dot as the decimal separator. int stores integers; converting double to int discards the fractional part towards zero, provided that the result is representable.\n\nchar marker = \'A\'; stores one character code unit written in single quotation marks; "A" is a string literal, not a char. A Russian character usually occupies several bytes in UTF-8, so one char cannot be promised to hold any letter. bool ready = true; stores true or false. Without special formatting, printing a bool produces 1 or 0.\n\nFor a fixed number of decimal places, include <iomanip> and output std::fixed << std::setprecision(2). This changes stream formatting, not the stored number. Valid numeric input in these tasks uses a decimal dot.',
        "microscope": "Most decimal fractions cannot be represented exactly in binary floating point. Formatting a number to two decimal places does not turn calculations into exact monetary arithmetic. Real monetary amounts commonly use integer minor units or another deliberately chosen representation. Here, double is a learning model for measurements.",
        "recap": "Numbers without quotation marks, one char in single quotation marks, text in double quotation marks. Keep formatting separate from calculation.",
    },
    "cpp.types.distance": {
        "title": "Laser rangefinder", "prompt": "Input: two nonnegative double distances from 0 to 1000, using a decimal dot. Print their sum with exactly two digits after the decimal point.",
        "hints": ["Use double for fractional values.", "Set fixed and setprecision(2) before printing the sum."],
        "explanation": "With fixed, precision 2 means two digits after the decimal point.",
    },
    "cpp.types.bool": {
        "title": "State indicators", "prompt": "Predict the program's exact output. Preserve spaces and line breaks.",
        "hints": ["A char is printed as a character.", "Without boolalpha, false is printed as 0."],
        "explanation": "This is the standard bool formatting of an unmodified output stream.",
    },
    "cpp.types.badge": {
        "title": "Sector code", "prompt": "Input: one uppercase Latin letter. Read it into a char and print Sector: followed by one space and the letter.",
        "hints": ["A char is sufficient for one Latin letter.", "Read into a variable, not a literal."],
        "explanation": "The Latin-letter restriction avoids confusing a char with a multibyte Russian character.",
    },
    "cpp.types.precision": {
        "title": "Precision is not magic", "prompt": "What does fixed << setprecision(2) guarantee when printing a double?",
        "choices": {"Любая десятичная дробь хранится точно": "Every decimal fraction is stored exactly", "В выводе два знака после точки": "The output has two digits after the decimal point", "Все последующие вычисления становятся целочисленными": "All subsequent calculations become integer calculations"},
        "hints": ["This is an output-stream setting.", "It does not change the variable's type or value."],
        "explanation": "A rounded display does not remove the limited precision of floating point.",
    },
    "cpp.types.temperature": {
        "title": "Average temperature", "prompt": "Input: two double measurements from −100 to 100. Print their arithmetic mean with one digit after the decimal point.",
        "hints": ["Add the two measurements first.", "Use parentheses around a + b before dividing by 2.0."],
        "explanation": "The parentheses express the mean's formula. The operands are double, so the division is floating-point division.",
    },
    "cpp.tickets": {
        "title": "Mini-project: ticket office", "summary": "Combine input, state and an exact report.",
        "theory": "At the ticket office, prices are conveniently stored as whole coins when the task does not require fractional monetary amounts. Read the input values first, calculate the cost and remaining amount next, then format the report. Do not mix input prompts into the required output.\n\nThis mini-project guarantees a sufficient budget, so no branching is needed. To handle arbitrary user input, you would need validation and decisions, which are upcoming topics. Distinguish task guarantees from language guarantees.",
        "microscope": "Input constraints are part of the task contract. For example, paid ≥ price * count lets you calculate nonnegative change without if. That does not make the program safe for every possible input. A real application validates input separately.",
        "recap": "Identify the units, constraints and output format. Save intermediate results using clear names.",
    },
    "cpp.tickets.total": {
        "title": "Print the receipt", "prompt": "Input: price p (0–100), quantity n (0–100), payment paid (from p*n to 20000). Print two lines: Total: <cost> and Change: <change>.",
        "hints": ["Cost is a product; change is a difference.", "Store the cost in total and use it twice."],
        "explanation": "An intermediate variable reduces the chance of using inconsistent values in different parts of the report.",
    },
    "cpp.tickets.trace": {
        "title": "Ticket-office history", "prompt": "Predict the program's exact output. Preserve spaces and line breaks.",
        "hints": ["receipt is initialized before balance changes.", "The subtraction does not change the copy that already exists."],
        "explanation": "The saved copy represents an earlier state.",
    },
    "cpp.tickets.packages": {
        "title": "Two passenger groups", "prompt": "Input: adult (0–20), child (0–20). An adult ticket costs 12 coins and a child ticket costs 7. Print the total cost.",
        "hints": ["Calculate each group's cost separately.", "Add adult * 12 and child * 7."],
        "explanation": "Multiplication happens before addition; the expression represents the two groups.",
    },
    "cpp.tickets.contract": {
        "title": "What does the task guarantee?", "prompt": "The task guarantees valid input and sufficient payment. What follows from this?",
        "choices": {"Любой пользовательский ввод безопасен": "Every possible user input is safe", "Для решения этой задачи можно не добавлять ветвление для нехватки денег": "This task can be solved without branching for insufficient payment", "Тип int может хранить любое число": "int can store any number"},
        "hints": ["The guarantees apply only to this task's inputs.", "Do not extend this contract to every possible value."],
        "explanation": "The task's tests respect its constraints. A real product needs additional validation.",
    },
    "cpp.tickets.budget": {
        "title": "Expedition budget remaining", "prompt": "Input: budget (0–20000), price (0–100), crew (0–100), with budget ≥ price*crew. Print crew, total cost and remaining budget on three separate lines with no labels.",
        "hints": ["The output order differs from the input order.", "The intermediate total is used on two lines."],
        "explanation": "Choosing the output order and saving the calculated cost combine the skills from the whole section.",
    },
}

SKILLS = {"int": "int", "cin": "cin", "арифметика": "arithmetic", "присваивание": "assignment", "состояние": "state", "обмен": "swapping", "типы": "types", "форматирование": "formatting", "double": "double", "мини-проект": "mini-project", "ввод": "input"}

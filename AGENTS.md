# Project context

- `MASTER_PROMPT.md` is the Russian product specification. It is now plain UTF-8 (previously RTF); read it directly. Consult it before implementation; the constraints below are not the full specification.
- Start with `PROJECT_PLAN.md` (resume point) and `VERIFICATION.md` (verified vs blocked checks). XCUITest automation and full visual/accessibility acceptance are not equivalent to the internal UI smoke test.

## Commands and boundaries

- Use `bash scripts/test.sh` (Swift Testing), `--filter ProgressTests` for focused persistence tests; `bash scripts/build.sh` produces `dist/CodePath.app`. `bash scripts/run.sh` keeps development progress in `.local-data/`, not the user's Application Support folder.
- Scripts select `/Applications/Xcode.app` via `DEVELOPER_DIR` and keep caches/artifacts inside `.build/`; do not change global `xcode-select` or system permissions. Target is macOS 26, tested on arm64.
- `CodePath.xcodeproj` is the native app; its local package dependency is `LearningCore`. The SwiftPM executable target is deliberately named **CodePathApp**, not CodePath, to avoid Xcode test-host resolution conflicts.
- `LearningCore` must stay free of SwiftUI/AppKit. Storage uses versioned Codable JSON with atomic writes, backup, advisory lock, and revision checks; retain unknown exercise IDs and distinguish an empty draft from no draft.
- New editor preferences must decode old schema-1 documents with defaults. Syntax colors use TextKit temporary attributes: never change source text, selection, undo, or copying for styling. The ruler uses the editor's own clip view (ancestor clipping hides offscreen lesson editors), and line/token offsets are UTF-16.
- Author course changes in `scripts/content_*.py`, regenerate with `PYTHONDONTWRITEBYTECODE=1 python3 scripts/generate_content.py`, then run `scripts/verify.sh`. `generate_content.py --check` checks reproducibility without overwriting JSON. Reference compilation/fixtures are developer-only, isolated under `.build/content-check/`.
- SwiftPM's resource bundle belongs in the packaged app's **Contents/Resources**, not Contents/MacOS. Build/signature success alone did not catch this; verify an actual launch.

## Implementation constraints

- Keep the native, Russian-language, offline app free of mandatory accounts, telemetry, subscriptions, and web wrappers.
- Before choosing a deployment target or project setup, inspect installed macOS, Xcode, SDKs, and Swift. Full system Liquid Glass targets macOS 26+; do not substitute a custom imitation on older systems.
- First version must **not compile or execute user code**, integrate AI, collect API keys, or simulate either feature. Compiling/running reference C++ solutions during development is explicitly allowed for content verification.
- Never grade free-form C++ by comparing source text with a reference solution. Auto-check only unambiguous answers; code-writing exercises use saved drafts, optional reference solutions, and self-completion clearly distinguished from automatic verification.
- Only C++ has a working course; Python, JavaScript, Java, and Rust are unavailable “Скоро” cards. Keep core course models language-neutral for later expansion.
- Keep structured, versioned course content outside UI components, and learning/checking/progress logic independent of presentation. Persist progress using stable IDs, not array positions; content reordering and schema updates must preserve drafts and results.

## Content and verification

- Teach modern C++17/C++20 progressively to absolute beginners: roughly 80% practice and 20% deeper understanding. Stepik is a pedagogical reference only; do not copy its exercises or materials.
- Reveal hints progressively and keep solutions hidden by default. Verify examples and reference answers; distinguish standard-guaranteed behavior from implementation-specific behavior and undefined behavior.
- Validate content loading, unique IDs, references, and required answer fields; test persistence across relaunch and content changes, not just in-memory state.
- Calculate actual course counts from JSON, not the planning table. Keep `README.md`, `PROJECT_PLAN.md`, and verification results honest about checks that were blocked or not executed.

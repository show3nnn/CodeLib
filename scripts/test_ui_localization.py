import json
import re
from pathlib import Path
import unittest
from generate_ui_localization import catalog, placeholders, source_files
import ui_en


class UICatalogTests(unittest.TestCase):
    def test_compiler_manifest_matches_sources_and_authoring(self):
        root = Path(__file__).resolve().parents[1]
        manifest = json.loads((root / "localization/ui/extraction.json").read_text())
        self.assertEqual(manifest["sourceFiles"], source_files(root))
        value = catalog(manifest, ui_en.TEXTS)
        self.assertEqual(value["sourceLanguage"], "ru")
        self.assertEqual(len(ui_en.TEXTS), len(manifest["entries"]))
        self.assertEqual(set(value["strings"]), set(ui_en.TEXTS))
        self.assertTrue(all(not re.search("[А-Яа-яЁё]", text) for text in ui_en.TEXTS.values()))
        self.assertTrue(all(not location.startswith("/") for locations in manifest["entries"].values() for location in locations))
        # These formerly dynamic String parameters must stay visible to Apple's extraction.
        for key in ["С возвращением, %@.", "Лаборатория кода", "ВАША ЛАБОРАТОРИЯ", "уроков завершено",
                    "проверено автоматически", "Не только точки с запятой", "Первый урок",
                    "Секретное достижение", "Условие откроется после получения награды.",
                    "Новое достижение · %@", "Получено · %@", "Учтено из прежнего прогресса · %@",
                    "Алгоритмы", "Исследование", "Мастерство", "Настойчивость", "Первые шаги", "Практика",
                    "Мои курсы", "Мой прогресс", "Программа C++", "Достижения", "Написать код", "Числовой ответ",
                    "Не завершено", "Проверено автоматически", "Отмечено вами", "Инициал имени", "Фотография",
                    "Не удалось экспортировать: %@", "Импорт отменён, текущие данные сохранены: %@",
                    "Сброс не выполнен: %@", "Восстановление не выполнено: %@",
                    "Версия данных %lld не поддерживается. Файл не изменён.",
                    "Перевод не готов: отсутствует %lld полей, неизвестных полей %lld",
                    "Не удалось сохранить профиль.", "Перевод относится к другому типу ресурса",
                    "Перевод ресурса ещё не прошёл содержательную рецензию",
                    "Полный перевод ресурса %@ для %@ пока недоступен",
                     "Изменения не сохранены", "Выйти без сохранения", "Остаться",
                     "Технические сведения", "Скопировать диагностику",
                     "%lld задание · ~%lld мин", "%lld задания · ~%lld мин",
                     "%lld заданий · ~%lld мин", "%lld из %lld задания",
                     "%lld из %lld заданий", "%lld из %lld задания завершено",
                     "%lld из %lld заданий завершено",
                     "задание завершено", "задания завершено", "заданий завершено",
                     "урок завершён", "урока завершено", "уроков завершено",
                     "достижение", "достижения", "достижений",
                     "%@ · %@ · %@", "%@  /  %@  /  %@",
                     "%lld раздел", "%lld раздела", "%lld разделов",
                     "%lld урок", "%lld урока", "%lld уроков",
                     "%lld задание", "%lld задания", "%lld заданий",
                     "%lld/%lld урок", "%lld/%lld урока", "%lld/%lld уроков",
                     "%lld/%lld раздел", "%lld/%lld раздела", "%lld/%lld разделов",
                     "stdout", "stderr · диагностика", "ввод", "ожидалось", "получено", "(пусто)",
                     "Вывод совпал", "Другой вывод", "Лимит процессорного времени", "Среда недоступна",
                      "Ваш профиль", "От первой строки к самостоятельному коду",
                      "Показать меньше", "Все задания для повторения (%lld)",
                      "Задание уже проверено на примерах", "Отметить выполнение без автопроверки",
                      "Скрыть теорию", "Теория", "Не сохранено", "Сохранено локально",
                      "Нужен намёк", "Раскрыть подсказку", "Верно. %@",
                      "Пока не совпало. Проверьте условие, формат и значения; можно раскрыть намёк.",
                      "Повторить сохранение", "Отметить прочитанным",
                     "Диагностика системы может быть на другом языке. Данные никуда не отправляются."]:
            self.assertIn(key, manifest["entries"])

    def test_unknown_empty_and_changed_placeholders_are_rejected(self):
        manifest = dict(entries={"Код: %lld пт": ["Sources/CodePath/SettingsView.swift:1"]})
        for translations in [{"unknown": "Unknown"}, {"Код: %lld пт": " "}, {"Код: %lld пт": "Code: %@ pt"}]:
            with self.assertRaises(ValueError): catalog(manifest, translations)
        self.assertEqual(placeholders("%lld / %lld"), placeholders("%lld of %lld"))
        self.assertNotEqual(placeholders("%02lld %.2f %%"), placeholders("%lld %.3f %%"))
        self.assertEqual(catalog(manifest, {"Код: %lld пт": "Code: %lld pt"})["version"], "1.0")

    def test_english_plural_keys_match_selected_forms(self):
        for key, translation in {
            "%lld задание": "%lld task",
            "%lld заданий": "%lld tasks",
            "%lld из %lld задания": "%lld of %lld task",
            "%lld из %lld заданий": "%lld of %lld tasks",
            "%lld/%lld урок": "%lld/%lld lesson",
            "%lld/%lld уроков": "%lld/%lld lessons",
        }.items():
            self.assertEqual(ui_en.TEXTS[key], translation)

    def test_code_checking_descriptions_distinguish_self_review(self):
        root = Path(__file__).resolve().parents[1]
        manifest = json.loads((root / "localization/ui/extraction.json").read_text())
        for key in (
            "C++17 запускается в одноразовой изолированной среде. Кодовые задания с автопроверкой проверяются на примерах из условия; остальные кодовые задания — самостоятельно. AI нет.",
            "C++17 запускается офлайн в изолированной Linux-среде без доступа к файлам Mac. Кодовые задания с автопроверкой проверяются на примерах из условия; остальные кодовые задания — самостоятельно. AI-помощника нет.",
        ):
            self.assertIn(key, manifest["entries"])
            self.assertIn("other code tasks are self-reviewed", ui_en.TEXTS[key])


if __name__ == "__main__":
    unittest.main()

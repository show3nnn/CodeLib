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
        for key in ["С возвращением, %@!", "Ваша лаборатория кода", "уроков завершено",
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
                    "Диагностика системы может быть на другом языке. Данные никуда не отправляются."]:
            self.assertIn(key, manifest["entries"])

    def test_unknown_empty_and_changed_placeholders_are_rejected(self):
        manifest = dict(entries={"Код: %lld пт": ["Sources/CodePath/SettingsView.swift:1"]})
        for translations in [{"unknown": "Unknown"}, {"Код: %lld пт": " "}, {"Код: %lld пт": "Code: %@ pt"}]:
            with self.assertRaises(ValueError): catalog(manifest, translations)
        self.assertEqual(placeholders("%lld / %lld"), placeholders("%lld of %lld"))
        self.assertNotEqual(placeholders("%02lld %.2f %%"), placeholders("%lld %.3f %%"))
        self.assertEqual(catalog(manifest, {"Код: %lld пт": "Code: %lld pt"})["version"], "1.0")


if __name__ == "__main__":
    unittest.main()

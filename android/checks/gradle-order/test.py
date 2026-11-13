import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from runpy import run_path

script = Path(__file__).with_name("check.py")
check = run_path(script)["check"]


class GradleOrderTest(unittest.TestCase):
    def errors(self, source):
        return check(source, "settings.gradle.kts")

    def test_includes_across_calls_and_multiline_arguments(self):
        errors = self.errors('include(":b")\ninclude(\n    ":a",\n    ":c",\n)')
        self.assertEqual(errors, [
            "settings.gradle.kts:3: include must be sorted: ':b' precedes ':a'"
        ])
        self.assertFalse(self.errors('include(":a", ":b")\ninclude(":c")'))

    def test_comments_strings_and_repositories_are_not_declarations(self):
        self.assertFalse(self.errors('''
            // include(":z", ":a")
            val text = """include(":z", ":a")"""
            repositories { mavenCentral(); google() }
            include(":a", ":b")
        '''))

    def test_character_literals_do_not_change_declaration_nesting(self):
        for literal in ["'('", "')'", "'['", "']'", "'{'", "'}'", r"'\''", r"'\\'"]:
            with self.subTest(literal=literal):
                self.assertEqual(
                    self.errors(f'val marker = {literal}\ninclude(":b", ":a")'),
                    ["settings.gradle.kts:2: include must be sorted: ':b' precedes ':a'"],
                )

    def test_each_dependency_configuration_is_sorted_independently(self):
        self.assertFalse(self.errors('''
            dependencies {
                implementation("a:lib:2")
                testImplementation("z:test:1")
                implementation("b:lib:1")
            }
        '''))
        errors = self.errors('''
            dependencies {
                implementation("b:lib:1")
                testImplementation("a:test:1")
                implementation("a:lib:2")
            }
        ''')
        self.assertEqual(len(errors), 1)
        self.assertIn("implementation must be sorted: 'b:lib' precedes 'a:lib'", errors[0])

    def test_strings_preserve_following_declarations(self):
        for expression in [
            'val endpoint = "https://ente.io"',
            'val label = "Marker: ${listOf(")").single()}"',
            'val label = """Marker: ${listOf("}").single()}"""',
            'val label = "Nested: ${"inner ${listOf("]").single()}"}"',
            'val label = "Value: ${run { /* } */ "}" }}"',
        ]:
            with self.subTest(expression=expression):
                self.assertEqual(
                    self.errors(f'{expression}; include(":b", ":a")'),
                    ["settings.gradle.kts:1: include must be sorted: ':b' precedes ':a'"],
                )

    def test_named_dependency_coordinates_mix_with_string_notation(self):
        errors = self.errors('''
            dependencies {
                implementation(name = "lib", version = "1", group = "z")
                implementation("a:lib:1")
            }
        ''')
        self.assertEqual(len(errors), 1)
        self.assertIn("implementation must be sorted: 'z:lib' precedes 'a:lib'", errors[0])

    def test_build_script_file_filters_are_not_project_includes(self):
        self.assertFalse(check('''
            tasks.register<Copy>("first") { include("z/**") }
            tasks.register<Copy>("second") { include("a/**") }
        ''', "build.gradle.kts"))

    def test_projects_platforms_catalogs_and_add(self):
        for first, second, expected in [
            ('project(":packages:z")', 'project(":packages:a")', "':packages:z' precedes ':packages:a'"),
            ('project(path = ":packages:z")', 'project(path = ":packages:a")', "':packages:z' precedes ':packages:a'"),
            ('project(path = ":packages:z", configuration = "default")', 'project(":packages:a")', "':packages:z' precedes ':packages:a'"),
            ('platform("z:bom:1")', 'enforcedPlatform("a:bom:1")', "'z:bom' precedes 'a:bom'"),
            ('libs.z', 'libs.a', "'libs.z' precedes 'libs.a'"),
        ]:
            with self.subTest(first=first):
                errors = self.errors(f'dependencies {{ api({first}); api({second}) }}')
                self.assertEqual(len(errors), 1)
                self.assertIn(expected, errors[0])
                self.assertFalse(self.errors(f'dependencies {{ api({second}); api({first}) }}'))
        self.assertEqual(len(self.errors('''
            dependencies { add("implementation", "z:lib:1"); implementation("a:lib:1") }
        ''')), 1)

    def test_dependency_customization_is_not_another_declaration(self):
        self.assertFalse(self.errors('''
            dependencies {
                implementation("a:lib:1") {
                    exclude(group = "z")
                    exclude(group = "a")
                }
                implementation("b:lib:1")
            }
        '''))

    def test_cli_excludes_build_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ["build/build.gradle.kts", ".gradle/build.gradle.kts"]:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('dependencies { api("z:lib:1"); api("a:lib:1") }')
            result = subprocess.run([sys.executable, script, root], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            (root / "settings.gradle.kts").write_text('include(":z", ":a")')
            result = subprocess.run([sys.executable, script, root], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn("include must be sorted", result.stderr)


if __name__ == "__main__":
    unittest.main()

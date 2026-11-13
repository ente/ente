import os
import re
import sys
from collections import defaultdict
from pathlib import Path

TOKEN = re.compile(r'''//[^\n]*|/\*|"""|"|'(?:\\.|[^'\\])*'|`[^`]*`|\w+|[^\s]''')
COMMENT = re.compile(r'/\*|\*/')


def parse(source):
    root = []
    stack = [root]
    for value, offset, _ in tokens(source):
        if value in (")", "}", "]"):
            stack.pop()
            continue
        children = []
        stack[-1].append((value, offset, children))
        if value in ("(", "{", "["):
            stack.append(children)
    return root


def tokens(source, start=0):
    while match := TOKEN.search(source, start):
        value = match.group()
        start = match.end()
        if value.startswith("//"):
            continue
        if value == "/*":
            depth = 1
            start = len(source)
            for marker in COMMENT.finditer(source, match.end()):
                depth += 1 if marker.group() == "/*" else -1
                if depth == 0:
                    start = marker.end()
                    break
            continue
        if value in ('"', '"""'):
            start = string_end(source, start, value)
        yield source[match.start():start], match.start(), start


def string_end(source, offset, quote):
    while offset < len(source):
        if source.startswith(quote, offset):
            return offset + len(quote)
        if quote == '"' and source[offset] == "\\":
            offset += 2
        elif source.startswith("${", offset):
            depth = 1
            for value, _, end in tokens(source, offset + 2):
                if value == "{":
                    depth += 1
                elif value == "}":
                    depth -= 1
                if depth == 0:
                    offset = end
                    break
            else:
                return len(source)
        else:
            offset += 1
    return offset


def calls(nodes):
    for index, (name, offset, _) in enumerate(nodes[:-1]):
        if index and nodes[index - 1][0] in (".", "fun"):
            continue
        bracket, _, arguments = nodes[index + 1]
        if name in ("if", "when", "for", "while", "catch"):
            continue
        if name.isidentifier() and bracket in ("(", "{"):
            yield name, offset, bracket, arguments


def walk(nodes):
    yield nodes
    for _, _, children in nodes:
        if children:
            yield from walk(children)


def arguments(nodes):
    result = [[]]
    for node in nodes:
        if node[0] == ",":
            result.append([])
        else:
            result[-1].append(node)
    return result


def dependency_key(nodes):
    if len(nodes) == 1 and nodes[0][0].startswith('"'):
        value = nodes[0][0].strip('"')
        return value if value.startswith(":") else ":".join(value.split(":")[:2])
    if len(nodes) == 2 and nodes[0][0] in ("project", "platform", "enforcedPlatform"):
        return dependency_arguments_key(arguments(nodes[1][2]))
    if nodes and all(value.isidentifier() or value == "." for value, _, _ in nodes):
        return "".join(value for value, _, _ in nodes)
    return None


def dependency_arguments_key(args):
    named = {
        arg[0][0]: dependency_key(arg[2:])
        for arg in args
        if len(arg) >= 3 and arg[1][0] == "="
    }
    if named.get("group") is not None and named.get("name") is not None:
        return f'{named["group"]}:{named["name"]}'
    if named.get("path") is not None:
        return named["path"]
    return dependency_key(args[0])


def check(source, path):
    includes = []
    groups = []
    for nodes in walk(parse(source)):
        for name, offset, bracket, body in calls(nodes):
            if name == "include" and bracket == "(" and Path(path).name == "settings.gradle.kts":
                includes.extend(
                    (value.strip('"'), position)
                    for value, position, _ in body
                    if value.startswith('"') and "$" not in value
                )
            if name != "dependencies" or bracket != "{":
                continue
            dependencies = defaultdict(list)
            for configuration, position, opening, declaration in calls(body):
                if opening != "(":
                    continue
                args = arguments(declaration)
                if configuration == "add" and len(args) > 1:
                    configuration = dependency_key(args.pop(0))
                key = dependency_arguments_key(args)
                if configuration and key is not None:
                    dependencies[configuration].append((key, position))
            groups.extend(dependencies.items())
    groups.append(("include", sorted(includes, key=lambda entry: entry[1])))
    errors = []
    for group, entries in groups:
        for (previous, _), (current, offset) in zip(entries, entries[1:]):
            if previous > current:
                line = source.count("\n", 0, offset) + 1
                errors.append(
                    f"{path}:{line}: {group} must be sorted: {previous!r} precedes {current!r}"
                )
    return errors


def main(root):
    errors = []
    for directory, children, files in os.walk(root):
        relative = Path(directory).relative_to(root)
        children[:] = sorted(child for child in children if child not in ("build", ".gradle"))
        for name in sorted(files):
            if name.endswith(".gradle.kts"):
                errors.extend(check((Path(directory) / name).read_text(), relative / name))
    for error in errors:
        print(error, file=sys.stderr)
    return bool(errors)


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1])))

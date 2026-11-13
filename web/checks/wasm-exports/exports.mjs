import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import ts from "typescript";

const isProductionSource = (source) =>
    !source.isDeclarationFile &&
    !/\/(node_modules|tests|__tests__)\/|\.(test|spec)\.[^/]+$/.test(
        source.fileName,
    );

const declarationKey = (node) => `${node.getSourceFile().fileName}:${node.pos}`;

export function rustExports(files) {
    const exports = new Map();
    for (const file of files) {
        const source = readFileSync(file, "utf8");
        const add = (name, offset) => {
            if (exports.has(name))
                throw new Error(`Duplicate Rust WASM export: ${name}`);
            exports.set(name, {
                file,
                name,
                line: source.slice(0, offset).split("\n").length,
            });
        };
        const jsName = (attributes, fallback) =>
            /js_name\s*=\s*"?(\w+)/.exec(attributes ?? "")?.[1] ?? fallback;
        const declaration =
            /^#\[wasm_bindgen(?:\(([^)]*)\))?\]\s*pub (?:async )?fn (\w+)/gm;
        for (const match of source.matchAll(declaration)) {
            add(jsName(match[1], match[2]), match.index);
        }
        const impl =
            /^#\[wasm_bindgen(?:\([^)]*\))?\]\s*impl (\w+) \{([\s\S]*?)^\}/gm;
        for (const block of source.matchAll(impl)) {
            const method =
                /^    (?:#\[wasm_bindgen(?:\(([^)]*)\))?\]\s*)?pub (?:async )?fn (\w+)/gm;
            const offset = block.index + block[0].indexOf(block[2]);
            for (const match of block[2].matchAll(method)) {
                const name = /\bconstructor\b/.test(match[1] ?? "")
                    ? "constructor"
                    : jsName(match[1], match[2]);
                add(`${block[1]}.${name}`, offset + match.index);
            }
        }
    }
    return exports;
}

export function unusedExports(files, projects, rustOrigins = new Map()) {
    const candidates = new Map();
    for (const file of files) {
        const source = ts.createSourceFile(
            file,
            readFileSync(file, "utf8"),
            ts.ScriptTarget.Latest,
            true,
        );
        const add = (node, qualifiedName) => {
            if (
                (!node.name && !qualifiedName) ||
                (source.isDeclarationFile && node.name?.getText() === "start")
            )
                return;
            if (
                node.name &&
                (ts.isObjectBindingPattern(node.name) ||
                    ts.isArrayBindingPattern(node.name))
            ) {
                for (const element of node.name.elements) add(element);
                return;
            }
            const name = qualifiedName ?? node.name.getText();
            const origin = rustOrigins.get(file)?.get(name);
            if (source.isDeclarationFile && rustOrigins.has(file) && !origin) {
                throw new Error(`${file}: cannot locate Rust export ${name}`);
            }
            candidates.set(declarationKey(node), {
                key: origin ? `${origin.file}:${name}` : declarationKey(node),
                file: origin?.file ?? file,
                name,
                line:
                    origin?.line ??
                    source.getLineAndCharacterOfPosition(node.getStart()).line +
                        1,
            });
        };
        for (const node of source.statements) {
            if (
                !node.modifiers?.some(
                    (m) => m.kind === ts.SyntaxKind.ExportKeyword,
                )
            )
                continue;
            if (ts.isFunctionDeclaration(node)) add(node);
            if (ts.isClassDeclaration(node) && !source.isDeclarationFile)
                add(node);
            if (ts.isClassDeclaration(node) && source.isDeclarationFile) {
                for (const member of node.members) {
                    if (
                        member.modifiers?.some(
                            (m) => m.kind === ts.SyntaxKind.PrivateKeyword,
                        ) ||
                        ["free", "[Symbol.dispose]"].includes(
                            member.name?.getText(),
                        )
                    )
                        continue;
                    const name = ts.isConstructorDeclaration(member)
                        ? "constructor"
                        : member.name.getText();
                    add(member, `${node.name.text}.${name}`);
                }
            }
            if (ts.isVariableStatement(node)) {
                for (const declaration of node.declarationList.declarations)
                    add(declaration);
            }
        }
    }

    const used = new Set();
    for (const { entryFiles, options } of projects) {
        const program = withWorkers(entryFiles, options);
        const checker = program.getTypeChecker();
        const referenced = new Set();
        const forwarded = new Map();
        const referenceDeclaration = (declaration) => {
            const key = declarationKey(declaration);
            referenced.add(key);
            const candidate = candidates.get(key);
            if (candidate) used.add(candidate.key);
        };
        const reference = (symbol) => {
            if (!symbol) return;
            if (symbol.flags & ts.SymbolFlags.Alias)
                symbol = checker.getAliasedSymbol(symbol);
            for (const root of checker.getRootSymbols(symbol)) {
                for (const declaration of root.declarations ?? []) {
                    referenceDeclaration(declaration);
                }
            }
        };
        for (const source of program.getSourceFiles()) {
            if (!isProductionSource(source)) continue;
            const visit = (node) => {
                if (
                    ts.isImportDeclaration(node) ||
                    ts.isExportDeclaration(node) ||
                    ts.isTypeNode(node)
                )
                    return;
                if (ts.isNewExpression(node) || ts.isCallExpression(node)) {
                    const signature = checker.getResolvedSignature(node);
                    if (signature?.declaration)
                        referenceDeclaration(signature.declaration);
                    if (signature?.declaration?.typeParameters?.length) {
                        const typeArguments =
                            checker.getTypeArgumentsForResolvedSignature(
                                signature,
                            );
                        for (const [index, parameter] of (
                            signature.declaration.typeParameters ?? []
                        ).entries()) {
                            if (
                                !parameter.constraint ||
                                !typeArguments?.[index]
                            )
                                continue;
                            const constraint = checker.getTypeFromTypeNode(
                                parameter.constraint,
                            );
                            for (const property of constraint.getProperties()) {
                                const target = checker.getPropertyOfType(
                                    typeArguments[index],
                                    property.name,
                                );
                                for (const declaration of property.declarations ??
                                    []) {
                                    const key = declarationKey(declaration);
                                    const targets = forwarded.get(key) ?? [];
                                    targets.push(target);
                                    forwarded.set(key, targets);
                                }
                            }
                        }
                    }
                }
                if (
                    ts.isBindingElement(node) &&
                    ts.isObjectBindingPattern(node.parent)
                ) {
                    const name = node.propertyName ?? node.name;
                    reference(
                        checker.getPropertyOfType(
                            checker.getTypeAtLocation(node.parent),
                            name.getText(),
                        ),
                    );
                } else if (ts.isShorthandPropertyAssignment(node)) {
                    reference(checker.getShorthandAssignmentValueSymbol(node));
                } else if (
                    ts.isIdentifier(node) &&
                    (node.parent.name !== node ||
                        ts.isPropertyAccessExpression(node.parent))
                ) {
                    reference(checker.getSymbolAtLocation(node));
                    const context = checker.getContextualType(node);
                    const type = checker.getTypeAtLocation(node);
                    if (context && type.symbol?.flags & ts.SymbolFlags.Module) {
                        for (const property of context.getProperties()) {
                            reference(type.getProperty(property.name));
                        }
                    }
                } else if (
                    ts.isElementAccessExpression(node) &&
                    ts.isStringLiteral(node.argumentExpression)
                ) {
                    reference(
                        checker.getPropertyOfType(
                            checker.getTypeAtLocation(node.expression),
                            node.argumentExpression.text,
                        ),
                    );
                }
                ts.forEachChild(node, visit);
            };
            visit(source);
        }
        for (const key of referenced) {
            for (const target of forwarded.get(key) ?? []) reference(target);
        }
    }
    return [
        ...new Map(
            [...candidates.values()]
                .filter(({ key }) => !used.has(key))
                .map(({ key, ...candidate }) => [key, candidate]),
        ).values(),
    ];
}

function withWorkers(entryFiles, options) {
    const roots = new Set(entryFiles);
    let program;
    for (;;) {
        program = ts.createProgram([...roots], options, undefined, program);
        const previousSize = roots.size;
        for (const source of program.getSourceFiles()) {
            if (!isProductionSource(source)) continue;
            const visit = (node) => {
                if (
                    ts.isNewExpression(node) &&
                    node.expression.getText(source) === "URL" &&
                    node.arguments?.[0] &&
                    ts.isStringLiteral(node.arguments[0])
                ) {
                    const file = resolve(
                        dirname(source.fileName),
                        node.arguments[0].text,
                    );
                    if (/\.[jt]sx?$/.test(file) && existsSync(file))
                        roots.add(file);
                }
                ts.forEachChild(node, visit);
            };
            visit(source);
        }
        if (roots.size === previousSize) return program;
    }
}

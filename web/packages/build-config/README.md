## ente-build-config

Build time configuration files. This can be thought of as a `devDependency` that exports various config files that our packages use at build time.

### Packaging

This is _not_ a TypeScript package, nor is it linted. It is not meant to be transpiled, it just exports static files that can be included verbatim.

### Debugging

Too see what tsc is seeing (e.g. when it is trying to type-check `ente-utils`), use `npm exec --workspace ente-utils -- tsc --showConfig`.

Similarly, to verify what ESLint is trying to do, use `npm exec --workspace ente-utils -- eslint --debug .`

If the issue is in VSCode, open the output window of the corresponding plugin, it might be telling us what's going wrong there. In particular, when changing the settings here, you might need to "Developer: Reload Window" in VSCode to get it to pick up the changes.

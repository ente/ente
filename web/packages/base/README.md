## ente-base

A base (+ UI layer) package for sharing code between our production apps.

This is a higher layer package than `ente-utils` (which is framework agnostic). This package is meant for sharing code between our Next.js apps that use React and MUI. Both the photos and auth apps use it.

Our smaller, Vite based apps, e.g. payments, don't use this.

### Packaging

This (internal) package exports a React TypeScript library. We rely on the importing project to transpile and bundle it.

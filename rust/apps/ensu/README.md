# Ensu Desktop

Desktop app for [Ensu](https://ente.com/ensu/). Built using Tauri.

## Building from source

1. Install [Node](https://nodejs.org), [Rust](https://www.rust-lang.org/tools/install) and CMake (e.g. `brew install cmake`).

2. Install web dependencies:

    ```sh
    cd web
    npm ci
    ```

3. Install desktop dependencies:

    ```sh
    cd rust/apps/ensu
    npm ci
    ```

4. Run the desktop app:

    ```sh
    npm run dev
    ```

The dev command starts the Ensu web app on port 3010 and launches Tauri, and changes in the web code will be hot reloaded.

> [!NOTE]
>
> If the relevant `package-lock.json` has not changed since your last `npm ci`, you can use `npm install` as a faster incremental alternative for both web and desktop.

To create a static build:

```sh
cd rust/apps/ensu
npm run build
```

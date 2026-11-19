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

## To Do evaluation

Run the model evaluation from `rust/`, with a local GGUF model:

```sh
ENSU_TEST_MODEL=/path/to/model.gguf cargo test --locked -p ente-ensu --test todo_eval todo_tool_calls_meet_accuracy_targets -- --ignored --nocapture
```

The evaluation fails below 95% routing accuracy or 90% call accuracy, or above
2% false change calls. Call accuracy includes the tool arguments after refinement.
False change calls include proposals that would need confirmation, not only changes
applied immediately. Reports are written before checking the targets; set
`ENSU_EVAL_OUT` to a JSON output path to retain them.

Tune against `crates/ensu/tests/data/todo_eval.jsonl`, then validate separately with
`ENSU_EVAL_CASES` set to the absolute path of
`crates/ensu/tests/data/todo_eval_holdout.jsonl`. Run both datasets for each supported
model. `ENSU_EVAL_MIN_ROUTE`, `ENSU_EVAL_MIN_CALL`, and
`ENSU_EVAL_MAX_FALSE_CHANGE` can explicitly override the targets for experiments;
use the defaults for PR validation.

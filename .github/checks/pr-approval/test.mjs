import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { join } from "node:path";
import test from "node:test";
import { runInNewContext } from "node:vm";

const workflow = join(import.meta.dirname, "../../workflows/pr-approval.yml");
const jobs = JSON.parse(
    execFileSync(
        "ruby",
        [
            "-ryaml",
            "-rjson",
            "-e",
            'puts JSON.generate(YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true).fetch("jobs"))',
            workflow,
        ],
        { encoding: "utf8" },
    ),
);
const pilot = { id: 293300083, login: "ashil-pilot" };
const human = { id: 77285023, login: "ashilkn" };
const otherTrusted = { id: 24503581, login: "mnvr" };
const untrusted = { id: 1, login: "untrusted" };

function allowed(author, sender, overrides = {}) {
    return runInNewContext(jobs["security-review"].if, {
        github: {
            repository: "ente/ente",
            run_attempt: 1,
            event: {
                pull_request: { user: author, changed_files: 1, draft: false },
                sender,
            },
            triggering_actor: sender.login,
            ...overrides,
        },
        contains: (values, value) => values.includes(value),
        fromJSON: JSON.parse,
    });
}

test("ashilkn can update an ashil-pilot PR through the exception", () => {
    assert.equal(allowed(pilot, human), true);
});

test("automatic approval requires a completed, clear security review", () => {
    for (const result of ["success", "failure", "cancelled", "skipped"])
        for (const clear of ["true", "false", undefined])
            assert.equal(
                runInNewContext(jobs.approve.if, {
                    needs: {
                        "security-review": {
                            result,
                            outputs: { "security-clear": clear },
                        },
                    },
                    github: {
                        triggering_actor: human.login,
                        event: { sender: human },
                    },
                }),
                result === "success" && clear === "true",
            );
});

test("other accounts cannot use the cross-account exception", () => {
    for (const author of [pilot, human, otherTrusted]) {
        assert.equal(allowed(author, author), true, author.login);
        for (const sender of [otherTrusted, untrusted]) {
            if (author.id === sender.id) continue;
            assert.equal(allowed(author, sender), false);
            assert.equal(allowed(sender, author), false);
        }
    }
    assert.equal(allowed(untrusted, untrusted), false);
});

test("ashilkn updates retain repository, rerun, draft, and file-count gates", () => {
    assert.equal(allowed(pilot, human, { repository: "fork/ente" }), false);
    assert.equal(allowed(pilot, human, { run_attempt: 2 }), false);
    assert.equal(
        allowed(pilot, human, { triggering_actor: pilot.login }),
        false,
    );
    for (const pull of [{ draft: true }, { changed_files: 101 }]) {
        assert.equal(
            allowed(pilot, human, {
                event: {
                    sender: human,
                    pull_request: {
                        user: pilot,
                        changed_files: 1,
                        draft: false,
                        ...pull,
                    },
                },
            }),
            false,
        );
    }
});

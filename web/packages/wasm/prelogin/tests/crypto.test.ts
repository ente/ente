import { expect, test } from "vitest";
import { boxSealOpenBytes } from "../index";

test("opens a libsodium sealed token as bytes", async () => {
    const token = await boxSealOpenBytes(
        "jVHae52Eixf5JkF0B0jZYR0U/KQ8ckCM631dw253O0bPMmpGHRPieCG/KRKk075x4STFEptJDw==",
        {
            publicKey: "W/Vcc7guviK+gPNDBmevVw+uJVamQV5rMNQGUwCqlH0=",
            privateKey: "UEatwduoOIZ7K7v90MNCPli1eXC1JnqQ9XlgkkqH8ZY=",
        },
    );
    expect(token).toStrictEqual(new Uint8Array([0, 1, 127, 128, 254, 255, 16]));
});

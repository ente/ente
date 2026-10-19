import { expect, test } from "vitest";
import { itemFormDataForSave } from "../src/components/create-item/item-form-fields-utils";

test("content-only notes derive a title from the first five words", () => {
    expect(
        itemFormDataForSave("note", {
            title: "  ",
            content: "  Remember where the spare key lives\nMore details  ",
        }),
    ).toEqual({
        title: "Remember where the spare key",
        content: "Remember where the spare key lives\nMore details",
    });
});

test("long generated note titles use mobile's 40-character limit", () => {
    expect(
        itemFormDataForSave("note", {
            content: "Antidisestablishmentarianism and several other details",
        }).title,
    ).toBe("Antidisestablishmentarianism and several...");
});

test("an explicit note title is kept, and clearing it regenerates the title", () => {
    expect(
        itemFormDataForSave("note", {
            title: "  My own title  ",
            content: "New content",
        }).title,
    ).toBe("My own title");
    expect(
        itemFormDataForSave("note", { title: "", content: "New content" })
            .title,
    ).toBe("New content");
});

test("cleared Thing and Secret fields are omitted on save", () => {
    expect(
        itemFormDataForSave("physicalRecord", {
            name: "  Spare key  ",
            location: "  ",
            notes: "",
        }),
    ).toEqual({ name: "Spare key" });
    expect(
        itemFormDataForSave("accountCredential", {
            name: "  Netflix  ",
            username: "",
            password: "",
            notes: "",
        }),
    ).toEqual({ name: "Netflix" });
});

test.each([" secret", "secret ", " secret ", "   "])(
    "saving a Secret preserves password whitespace: %j",
    (password) => {
        const data = itemFormDataForSave("accountCredential", {
            name: "  Account  ",
            username: "  user  ",
            password,
            notes: "  Notes  ",
        });
        expect(data).toEqual({
            name: "Account",
            username: "user",
            password,
            notes: "Notes",
        });
        expect(
            itemFormDataForSave("accountCredential", {
                ...data,
                name: "Renamed",
            }),
        ).toEqual({
            name: "Renamed",
            username: "user",
            password,
            notes: "Notes",
        });
    },
);

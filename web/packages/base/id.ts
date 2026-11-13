import { customAlphabet } from "nanoid";

// Exclude "-" for editor selection and "_" so prefixes remain unambiguous.
export const alphabet =
    "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

// The extra character compensates for the smaller alphabet.
const nanoid = customAlphabet(alphabet, 22);

export const newID = (prefix: string) => prefix + nanoid();

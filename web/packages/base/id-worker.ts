import { customAlphabet } from "nanoid/non-secure";
import { alphabet } from "./id";

const nanoid = customAlphabet(alphabet, 22);

export const newNonSecureID = (prefix: string) => prefix + nanoid();

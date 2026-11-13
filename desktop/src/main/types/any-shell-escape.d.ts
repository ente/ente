declare module "any-shell-escape" {
    declare const shellescape: (args: readonly string | string[]) => string;
    export default shellescape;
}

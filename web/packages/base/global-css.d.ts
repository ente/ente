declare module "*.module.css" {
    const classes: Readonly<Record<string, string>>;
    export default classes;
}

declare module "*.css";
declare module "@fontsource/*";
declare module "@fontsource-variable/*";

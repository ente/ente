export default {
    async fetch(request: Request) {
        switch (request.method) {
            case "OPTIONS":
                return handleOPTIONS();
            case "POST":
                return handlePOST(request);
            default:
                console.log(`Unsupported HTTP method ${request.method}`);
                return new Response(null, { status: 405 });
        }
    },
} satisfies ExportedHandler;

const handleOPTIONS = () =>
    new Response(null, {
        headers: {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Max-Age": "86400",
        },
    });

const handlePOST = async (request: Request) => {
    // {job="worker"} |= `[csp-report]` | json log="logs[0]" | keep log
    console.log("[csp-report]", await request.text());
    return new Response(null, { status: 200 });
};

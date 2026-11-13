export default {
    async fetch(request: Request) {
        switch (request.method) {
            default:
                console.log(`Unsupported HTTP method ${request.method}`);
                return new Response(null, { status: 405 });
        }
    },
} satisfies ExportedHandler;

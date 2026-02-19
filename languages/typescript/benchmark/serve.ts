const dir = import.meta.dir + "/dist";

Bun.serve({
  port: 3000,
  async fetch(req) {
    let path = new URL(req.url).pathname;
    if (path === "/") path = "/index.html";
    const file = Bun.file(dir + path);
    if (await file.exists()) return new Response(file);
    return new Response("Not found", { status: 404 });
  },
});

console.log("Serving at http://localhost:3000");

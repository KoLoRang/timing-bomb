// TimingBomb code-node template.
// Contract: define exactly one async function run(ctx); no import/require;
// interact with the outside world only through ctx; the return value is
// written to ctx.nodes.<this node's id>.output.
async function run(ctx) {
  // Input: the trigger payload (injected by `tb run <flowId> --input '<json>'`)
  const payload = ctx.trigger.payload || {};

  // Upstream node outputs: ctx.nodes.<nodeId>.output; inside loops: ctx.loop.item / ctx.loop.index
  const upstream = ctx.nodes["some-node-id"]?.output ?? null;

  // Tools: log / sleep / fail / http.fetch
  ctx.tools.log("payload:", JSON.stringify(payload));
  await ctx.tools.sleep(100); // milliseconds
  // const resp = await ctx.tools.http.fetch("https://example.com/api", {
  //   method: "POST",
  //   headers: { "Content-Type": "application/json" },
  //   body: { hello: "world" },
  // });
  // const data = resp.json();

  // Failure: throw or ctx.tools.fail("reason") (handled per node onError/retries)
  if (!payload.required) {
    ctx.tools.fail("missing required payload");
  }

  // Loop control (loop bodies only): return { $loop: "break" } / { $loop: "continue" }

  // Return any JSON value
  return { ok: true, receivedAt: new Date().toISOString() };
}

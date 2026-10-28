// TimingBomb 代码节点模板
// 契约：必须且只能定义 async function run(ctx)；禁止 import/require；
//       只能通过 ctx 与外界交互；返回值写入 ctx.nodes.<本节点id>.output。
async function run(ctx) {
  // 输入：触发 payload（tb run <flowId> --input '<json>' 注入）
  const payload = ctx.trigger.payload || {};

  // 上游节点输出：ctx.nodes.<nodeId>.output；循环内：ctx.loop.item / ctx.loop.index
  const upstream = ctx.nodes["some-node-id"]?.output ?? null;

  // 工具：log / sleep / fail / http.fetch
  ctx.tools.log("payload:", JSON.stringify(payload));
  await ctx.tools.sleep(100); // 毫秒
  // const resp = await ctx.tools.http.fetch("https://example.com/api", {
  //   method: "POST",
  //   headers: { "Content-Type": "application/json" },
  //   body: { hello: "world" },
  // });
  // const data = resp.json();

  // 失败：抛错或 ctx.tools.fail("原因")（按节点 onError/retries 策略处理）
  if (!payload.required) {
    ctx.tools.fail("missing required payload");
  }

  // 循环控制（仅 loop 体内）：return { $loop: "break" } / { $loop: "continue" }

  // 返回任意 JSON 值
  return { ok: true, receivedAt: new Date().toISOString() };
}

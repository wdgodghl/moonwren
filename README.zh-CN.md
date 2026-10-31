# MoonWren

MoonWren 是使用 MoonBit 实现、面向嵌入场景的 Wren 0.4.0 兼容解释器。项目的固定目标是执行 Wren 0.4.0 源码并提供明确的 MoonBit 宿主边界，而不是兼容 Wren C ABI、官方字节码、GC 时序或 `wren_cli` 的操作系统模块。

## 安装与最小使用

```text
moon add wdgodghl/moonwren@0.9.3
```

在使用方 `moon.pkg` 中导入 `wdgodghl/moonwren` 后：

```moonbit
fn main {
  match @moonwren.run("System.print(40 + 2)") {
    ProgramCompleted(_, output) => println(output[0])
    ProgramFailed(issues, _) => println(issues[0].render("demo.wren"))
  }
}
```

预期输出为 `42`。完整且会被自动验收的步骤见 [`VALIDATION.md`](VALIDATION.md) 和 [`docs/getting-started.md`](docs/getting-started.md)。

## 项目边界

- 固定兼容目标：Wren 0.4.0，参考提交 `4a18fc489f9ea3d253b20dd40f4cdad0d6bb40eb`。
- 支持一次性执行、持久化 `Vm`、Native CLI，以及浏览器/Node.js SDK。
- 核心运行时不直接访问文件、环境变量、进程或网络；宿主能力必须显式授予。
- 资源限制不是操作系统安全沙箱，互不信任的脚本仍应使用进程或容器隔离。

精确定义、实验性 API 和非目标见 [`docs/project-boundary.md`](docs/project-boundary.md) 与 [`docs/public-api.md`](docs/public-api.md)。

## 验证状态

- 331 个 MoonBit 行为测试分别运行于 wasm、wasm-gc、JavaScript 和 native，其中包括持久 VM、Fiber、热重载、GC 与宿主回调的组合不变量。
- 官方 Wren 0.4.0 `language` 与 `core` 套件：779 通过、0 失败、22 个上游标记为 `skip`/`nontest`。
- CI 还验证真实浏览器、Native CLI、核心执行路径覆盖率、公共 API 快照、仓库卫生、每日差分模糊测试和 10,000 次持久 VM 压力运行。
- 独立的 `moonwren-json-pipeline` 小型应用只从 Mooncakes 安装 MoonWren，并验证真实 JSONL 规则处理、宿主回调、资源限制和长期 VM 状态。

英文主文档、许可证和参考来源见 [`README.md`](README.md)、[`LICENSE`](LICENSE) 和 [`NOTICE`](NOTICE)。

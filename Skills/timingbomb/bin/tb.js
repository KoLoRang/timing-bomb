#!/usr/bin/env node
// tb launcher: picks the matching prebuilt binary from assets/ and execs it.
// The Go binaries cover darwin/linux/windows on amd64/arm64 without Node
// involvement at runtime — this shim only resolves the path.
"use strict";

const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const assets = {
  darwin: { arm64: "tb-darwin-arm64", x64: "tb-darwin-amd64" },
  linux: { arm64: "tb-linux-arm64", x64: "tb-linux-amd64" },
  win32: { arm64: "tb-windows-arm64.exe", x64: "tb-windows-amd64.exe" },
};

const arch = process.arch === "x64" ? "x64" : process.arch;
const name = (assets[process.platform] || {})[arch];
const bin = name ? path.join(__dirname, "..", "assets", name) : null;

if (!bin || !fs.existsSync(bin)) {
  console.error(
    `tb: no prebuilt binary for ${process.platform}/${process.arch}. ` +
      "See the package assets/ folder or build from the cli/ sources."
  );
  process.exit(1);
}

const result = spawnSync(bin, process.argv.slice(2), { stdio: "inherit" });
process.exit(result.status === null ? 1 : result.status);

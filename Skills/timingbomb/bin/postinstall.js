#!/usr/bin/env node
// Post-install pruning: the npm tarball carries all platform binaries; after
// install keep only the one matching this machine so the package stays slim.
"use strict";

const fs = require("fs");
const path = require("path");

const assets = {
  darwin: { arm64: "tb-darwin-arm64", x64: "tb-darwin-amd64" },
  linux: { arm64: "tb-linux-arm64", x64: "tb-linux-amd64" },
  win32: { arm64: "tb-windows-arm64.exe", x64: "tb-windows-amd64.exe" },
};

try {
  const arch = process.arch === "x64" ? "x64" : process.arch;
  const keep = (assets[process.platform] || {})[arch];
  const dir = path.join(__dirname, "..", "assets");
  if (!keep || !fs.existsSync(dir)) process.exit(0);
  for (const name of fs.readdirSync(dir)) {
    if (name !== keep) fs.rmSync(path.join(dir, name), { force: true });
  }
} catch {
  // Best effort only — never break the install.
}

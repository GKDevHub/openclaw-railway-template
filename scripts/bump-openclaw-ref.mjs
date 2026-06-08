import fs from "node:fs";

const owner = "openclaw";
const repo = "openclaw";
const token = process.env.GITHUB_TOKEN;
if (!token) {
  console.error("Missing GITHUB_TOKEN");
  process.exit(2);
}

async function gh(path) {
  const url = `https://api.github.com${path}`;
  const res = await fetch(url, {
    headers: {
      authorization: `Bearer ${token}`,
      accept: "application/vnd.github+json",
      "user-agent": "openclaw-railway-template-bot",
    },
  });
  if (!res.ok) {
    throw new Error(`GitHub API ${res.status}: ${await res.text()}`);
  }
  return res.json();
}

// The Dockerfile installs `openclaw@<version>` from npm. npm versions are the
// release tag without the leading "v" (e.g. tag v2026.6.1 -> npm 2026.6.1).
function tagToVersion(tag) {
  return tag.replace(/^v/, "");
}

function readCurrentVersion(dockerfile) {
  const m = dockerfile.match(/\nARG OPENCLAW_VERSION=([^\n]+)\n/);
  return m ? m[1].trim() : null;
}

function replaceVersion(dockerfile, next) {
  const re = /\nARG OPENCLAW_VERSION=([^\n]+)\n/;
  if (!re.test(dockerfile)) throw new Error("Could not find OPENCLAW_VERSION line");
  return dockerfile.replace(re, `\nARG OPENCLAW_VERSION=${next}\n`);
}

const latest = await gh(`/repos/${owner}/${repo}/releases/latest`);
const latestTag = latest.tag_name;
if (!latestTag) throw new Error("No tag_name in latest release response");
const latestVersion = tagToVersion(latestTag);

const dockerPath = "Dockerfile";
const docker = fs.readFileSync(dockerPath, "utf8");
const currentVersion = readCurrentVersion(docker);
if (!currentVersion) throw new Error("Could not parse current OPENCLAW_VERSION");

console.log(`current=${currentVersion} latest=${latestVersion}`);

if (currentVersion === latestVersion) {
  console.log("No update needed.");
  process.exit(0);
}

fs.writeFileSync(dockerPath, replaceVersion(docker, latestVersion));
console.log(`Updated ${dockerPath} to ${latestVersion}`);

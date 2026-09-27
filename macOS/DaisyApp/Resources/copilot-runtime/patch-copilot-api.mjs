import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const runtimeDirectory = path.dirname(fileURLToPath(import.meta.url));
const packageDirectory = path.join(runtimeDirectory, "node_modules", "copilot-api");
const packageManifestPath = path.join(packageDirectory, "package.json");
const entrypointPath = path.join(packageDirectory, "dist", "main.js");

const packageManifest = JSON.parse(await readFile(packageManifestPath, "utf8"));
if (packageManifest.version !== "0.7.0") {
  throw new Error(
    `Refusing to patch unsupported copilot-api version ${packageManifest.version}.`,
  );
}

let source = await readFile(entrypointPath, "utf8");

const replacements = [
  {
    description: "disable cross-origin browser access",
    original: "server.use(cors());",
    hardened: "// Daisy disables permissive CORS for this local credentialed service.",
  },
  {
    description: "remove the unauthenticated token endpoint",
    original: 'server.route("/token", tokenRoute);',
    hardened: "// Daisy does not expose copilot-api's unauthenticated /token route.",
  },
  {
    description: "bind the server to loopback",
    original: [
      "\tserve({",
      "\t\tfetch: server.fetch,",
      "\t\tport: options.port",
      "\t});",
    ].join("\n"),
    hardened: [
      "\tserve({",
      "\t\tfetch: server.fetch,",
      "\t\tport: options.port,",
      '\t\thostname: "127.0.0.1"',
      "\t});",
    ].join("\n"),
  },
  {
    description: "read Daisy's token from the child environment",
    original: [
      "\tawait ensurePaths();",
      "\tawait cacheVSCodeVersion();",
      "\tif (options.githubToken) {",
      "\t\tstate.githubToken = options.githubToken;",
      '\t\tconsola.info("Using provided GitHub token");',
      "\t} else await setupGitHubToken();",
    ].join("\n"),
    hardened: [
      "\tawait cacheVSCodeVersion();",
      "\tconst daisyGitHubToken = process.env.DAISY_GITHUB_TOKEN;",
      '\tif (!daisyGitHubToken) throw new Error("Missing GitHub token supplied by Daisy");',
      "\tstate.githubToken = daisyGitHubToken;",
      '\tconsola.info("Using GitHub token supplied by Daisy");',
    ].join("\n"),
  },
];

for (const replacement of replacements) {
  if (source.includes(replacement.hardened)) {
    continue;
  }

  const firstMatch = source.indexOf(replacement.original);
  const secondMatch = source.indexOf(
    replacement.original,
    firstMatch + replacement.original.length,
  );
  if (firstMatch < 0 || secondMatch >= 0) {
    throw new Error(`Could not safely ${replacement.description}.`);
  }

  source = source.replace(replacement.original, replacement.hardened);
}

await writeFile(entrypointPath, source, "utf8");

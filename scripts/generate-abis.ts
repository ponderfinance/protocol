import { readFileSync, writeFileSync, mkdirSync } from "fs";
import { join } from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Contracts to process
const contracts = [
  "PonderFactory",
  "PonderPair",
  "PonderRouter",
  "PonderToken",
  "PonderPriceOracle",
  "PonderMasterChef",
  "KKUBUnwrapper",
  "FiveFiveFiveLauncher",
  "LaunchToken",
  "FeeDistributor",
  "PonderStaking",
];

// Ensure directories exist
mkdirSync(join(dirname(__dirname), "src/abis"), { recursive: true });

// Process each contract
for (const contract of contracts) {
  try {
    // Read the artifact JSON
    const artifactPath = join(
      dirname(__dirname),
      `out/${contract}.sol/${contract}.json`
    );
    const artifact = JSON.parse(readFileSync(artifactPath, "utf8"));

    // Extract ABI and format as TS
    const abiTs = `export const ${contract.toLowerCase()}Abi = ${JSON.stringify(
      artifact.abi,
      null,
      2
    )} as const;\n`;

    // Write to file
    writeFileSync(
      join(dirname(__dirname), "src/abis", `${contract.toLowerCase()}.ts`),
      abiTs
    );

    console.log(`✅ Generated ABI for ${contract}`);
  } catch (error) {
    console.error(`❌ Error processing ${contract}:`, error);
  }
}

// Generate index file
const indexContent =
  contracts
    .map((name) => `export * from './${name.toLowerCase()}.js';`)
    .join("\n") + "\n";

writeFileSync(join(dirname(__dirname), "src/abis/index.ts"), indexContent);

// Generate main index file
writeFileSync(
  join(dirname(__dirname), "src/index.ts"),
  `export * from './abis/index.js';\n`
);

console.log("✅ Generated index files");

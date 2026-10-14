const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with:", deployer.address);
  const slot = await hre.ethers.deployContract("CyberbitSlot");
  await slot.waitForDeployment();
  console.log("CyberbitSlot (CBIT) deployed to:", await slot.getAddress());
  console.log("Paste this address into index.html -> Contract setup.");
}

main().catch((e) => { console.error(e); process.exitCode = 1; });

// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const { ethers } = require("hardhat");
const hre = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log(`Deploying contract with account:`);
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contracts to deploy
  const Rfa = await hre.ethers.getContractFactory("Rfa");
  const rfa = await Rfa.deploy();
  await rfa.deployed();
  console.log(`Token address: ${rfa.address}`);
  
  const Staking = await hre.ethers.getContractFactory("Staking");
  const staking = await hre.upgrades.deployProxy(Staking, [rfa.address], {initializer: 'initialize'});
  await staking.deployed;
  console.log(`\nproxy address: ${staking.address}\n`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

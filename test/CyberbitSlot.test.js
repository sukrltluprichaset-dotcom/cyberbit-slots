const { expect } = require("chai");
const hre = require("hardhat");
const { ethers } = hre;

describe("CyberbitSlot (CBIT)", () => {
  let slot, a, b;
  beforeEach(async () => {
    [a, b] = await ethers.getSigners();
    slot = await ethers.deployContract("CyberbitSlot");
  });

  it("exposes coin metadata and mints the initial faucet once", async () => {
    expect(await slot.symbol()).to.equal("CBIT");
    expect(await slot.decimals()).to.equal(0);
    await slot.claimInitialFaucet();
    expect(await slot.balanceOf(a.address)).to.equal(5000);
    expect(await slot.totalSupply()).to.equal(5000);
    await expect(slot.claimInitialFaucet()).to.be.revertedWith("Initial faucet already claimed");
  });

  it("is non-transferable", async () => {
    await expect(slot.transfer(b.address, 1)).to.be.revertedWith("CBIT is non-transferable");
    await expect(slot.approve(b.address, 1)).to.be.revertedWith("CBIT is non-transferable");
    await expect(slot.transferFrom(a.address, b.address, 1)).to.be.revertedWith("CBIT is non-transferable");
  });

  it("faucet requires initial claim and respects cooldown", async () => {
    await expect(slot.claimFaucet()).to.be.revertedWith("Claim the initial faucet first");
    await slot.claimInitialFaucet();
    await expect(slot.claimFaucet()).to.be.revertedWith("Faucet cooldown active");
    await ethers.provider.send("evm_increaseTime", [301]);
    await ethers.provider.send("evm_mine", []);
    await slot.claimFaucet();
    expect(await slot.balanceOf(a.address)).to.equal(7000);
  });

  it("rejects invalid bets and spends without balance", async () => {
    await slot.claimInitialFaucet();
    await expect(slot.spinMainSlot(77)).to.be.revertedWith("Invalid bet amount");
    await expect(slot.connect(b).spinMainSlot(50)).to.be.revertedWith("Insufficient CBIT balance");
  });

  it("spins keep supply consistent: supply == sum of balances", async () => {
    await slot.claimInitialFaucet();
    for (let i = 0; i < 60; i++) await slot.spinMainSlot(50);
    expect(await slot.totalSupply()).to.equal(await slot.balanceOf(a.address));
    const s = await slot.getPlayerState(a.address);
    expect(s.charge).to.equal(10);
  });

  it("bonus vault fills the meter and unlocks wheel spins", async () => {
    await slot.claimInitialFaucet();
    for (let i = 0; i < 10; i++) await slot.spinBonusVault();
    const s = await slot.getPlayerState(a.address);
    // 10 vault spins with no scatter (99.9% each) => at least one wheel spin unlocked
    expect(s.wheelSpins).to.be.gte(1);
    await slot.spinWheelOfSatoshi();
  });

  it("theoretical RTP of the main game is between 90% and 100%", () => {
    const w = { 1: 25, 2: 50, 3: 100, 4: 175, 0: 650 };
    const pay = { 1: 500, 2: 200, 3: 100, 4: 50 };
    let rtp = 0;
    for (const x of [0,1,2,3,4]) for (const y of [0,1,2,3,4]) for (const z of [0,1,2,3,4]) {
      const p = (w[x] * w[y] * w[z]) / 1e9;
      if (x === y && y === z && x !== 0) rtp += p * pay[x];
      else if ((x === y && x) || (y === z && y) || (x === z && x)) rtp += p * 5;
    }
    console.log("      theoretical RTP:", (rtp * 100).toFixed(2) + "%");
    expect(rtp).to.be.within(0.9, 1.0);
  });
});

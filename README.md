# Cyberbit Slots (CBIT)

Slot machine demo with its own in-game virtual coin, **CBIT**, running on an EVM testnet.

CBIT has no monetary value. It is non-transferable (transfer/approve always revert), only minted by the faucet and slot wins, and burned when you bet. Testnets only — do not deploy to mainnet.

## Files

- `contracts/CyberbitSlot.sol` — game + CBIT coin (read-side ERC-20, so wallets can display the balance)
- `index.html` — front end (ethers.js + MetaMask)
- `test/` — Hardhat tests, `scripts/deploy.js` — deploy script

## Quick start

```bash
npm install
cp .env.example .env        # fill in a THROWAWAY testnet key + RPC URL
npm test
npm run deploy:sepolia      # or deploy:bsctest
npm run serve               # open http://localhost:8080
```

In the page: Connect Wallet -> paste the deployed address -> Load Contract -> Claim 5,000 CBIT -> Spin.
Or deploy with Remix to a public testnet and paste the address.

## Game rules

- Bets: 50 / 100 / 250 / 500 CBIT. Paytable: 3x Bitcoin 500x, 3x Seven 200x, 3x Diamond 100x, 3x Ethereum 50x, any pair 5x.
- Theoretical return of the main game is about 96%.
- Each main spin charges the meter; Bonus Vault (200 CBIT) can hit a scatter or fill the meter to unlock a Wheel of Satoshi spin.
- Faucet: 5,000 CBIT once, then 2,000 every 5 minutes.

## Caveat

Randomness uses block data and is not secure. Fine for a demo; never use it with anything of real value.

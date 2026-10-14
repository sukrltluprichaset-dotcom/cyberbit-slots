// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title CyberbitSlot
/// @notice Slot machine simulation with an in-game virtual coin (CBIT).
///         For demo / testnet use only. CBIT has NO monetary value and is
///         deliberately NON-TRANSFERABLE: it exposes the read side of ERC-20
///         (name, symbol, decimals, totalSupply, balanceOf) so wallets and
///         explorers can display it, but transfer/approve always revert.
///         Randomness is a pseudo-RNG (keccak256 over block data) and is NOT
///         secure — do not use this contract for real-money gambling.
contract CyberbitSlot {
    // ---------------------------------------------------------------------
    // Coin metadata (ERC-20 read interface, non-transferable)
    // ---------------------------------------------------------------------
    string public constant name = "Cyberbit Coin";
    string public constant symbol = "CBIT";
    uint8 public constant decimals = 0;
    uint256 public totalSupply;

    // ---------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------
    uint8 private constant NONE = 0;
    uint8 private constant BITCOIN = 1;
    uint8 private constant SEVEN = 2;
    uint8 private constant DIAMOND = 3;
    uint8 private constant ETHEREUM = 4;

    uint256 public constant INITIAL_FAUCET_AMOUNT = 5000;
    uint256 public constant FAUCET_AMOUNT = 2000;
    uint256 public constant FAUCET_COOLDOWN = 5 minutes;

    uint256 public constant BONUS_VAULT_COST = 200;
    uint256 public constant CHARGE_METER_MAX = 10;

    address public owner;
    uint256 private nonce;

    // ---------------------------------------------------------------------
    // Player state
    // ---------------------------------------------------------------------
    mapping(address => uint256) private _balances;
    mapping(address => bool) public hasClaimedInitialFaucet;
    mapping(address => uint256) public lastFaucetClaim;
    mapping(address => uint256) public chargeMeter;
    mapping(address => uint256) public wheelSpinsAvailable;
    mapping(address => uint256) public activeMultiplier; // applied to next main-slot win

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------
    /// @dev Emitted on mint (from = 0x0) and burn (to = 0x0) only.
    event Transfer(address indexed from, address indexed to, uint256 value);

    event FaucetClaimed(address indexed player, uint256 amount, uint256 newBalance);

    event SpinResult(
        address indexed player,
        uint8[3] reels,
        uint256 bet,
        uint256 payout,
        uint256 timestamp,
        bytes32 simulatedHash
    );

    event BonusVaultResult(
        address indexed player,
        bool scatterHit,
        uint256 payout,
        uint256 chargeLevel,
        uint256 timestamp,
        bytes32 simulatedHash
    );

    event WheelOfSatoshiResult(
        address indexed player,
        string prizeType,
        uint256 amount,
        uint256 timestamp,
        bytes32 simulatedHash
    );

    event SuperMegaWin(
        address indexed player,
        uint256 payout,
        uint256 multiplier,
        uint256 freeSpins,
        uint256 timestamp
    );

    constructor() {
        owner = msg.sender;
    }

    // ---------------------------------------------------------------------
    // Coin: read-only ERC-20 surface
    // ---------------------------------------------------------------------
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function transfer(address, uint256) external pure returns (bool) {
        revert("CBIT is non-transferable");
    }

    function approve(address, uint256) external pure returns (bool) {
        revert("CBIT is non-transferable");
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        revert("CBIT is non-transferable");
    }

    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    function _mint(address to, uint256 amount) private {
        if (amount == 0) return;
        totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) private {
        require(_balances[from] >= amount, "Insufficient CBIT balance");
        _balances[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    // ---------------------------------------------------------------------
    // Faucet
    // ---------------------------------------------------------------------
    function claimInitialFaucet() external {
        require(!hasClaimedInitialFaucet[msg.sender], "Initial faucet already claimed");
        hasClaimedInitialFaucet[msg.sender] = true;
        lastFaucetClaim[msg.sender] = block.timestamp;
        _mint(msg.sender, INITIAL_FAUCET_AMOUNT);
        emit FaucetClaimed(msg.sender, INITIAL_FAUCET_AMOUNT, _balances[msg.sender]);
    }

    function claimFaucet() external {
        require(hasClaimedInitialFaucet[msg.sender], "Claim the initial faucet first");
        require(
            block.timestamp >= lastFaucetClaim[msg.sender] + FAUCET_COOLDOWN,
            "Faucet cooldown active"
        );
        lastFaucetClaim[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
        emit FaucetClaimed(msg.sender, FAUCET_AMOUNT, _balances[msg.sender]);
    }

    function faucetCooldownRemaining(address player) external view returns (uint256) {
        uint256 nextClaim = lastFaucetClaim[player] + FAUCET_COOLDOWN;
        if (block.timestamp >= nextClaim) return 0;
        return nextClaim - block.timestamp;
    }

    // ---------------------------------------------------------------------
    // Pseudo-RNG helpers (NOT secure — demo purposes only)
    // ---------------------------------------------------------------------
    function _random(uint256 salt) private returns (uint256) {
        nonce++;
        return uint256(
            keccak256(
                abi.encodePacked(block.timestamp, block.prevrandao, msg.sender, nonce, salt)
            )
        );
    }

    /// @dev Symbol weights out of 1000, tuned so the main game's return-to-player
    ///      is roughly 96%: Bitcoin 2.5%, Seven 5%, Diamond 10%, Ethereum 17.5%, blank 65%.
    function _randomSymbol(uint256 rand, uint256 reel) private pure returns (uint8) {
        uint256 r = uint256(keccak256(abi.encodePacked(rand, reel))) % 1000;
        if (r < 25) return BITCOIN;
        if (r < 75) return SEVEN;
        if (r < 175) return DIAMOND;
        if (r < 350) return ETHEREUM;
        return NONE;
    }

    // ---------------------------------------------------------------------
    // Main slot
    // ---------------------------------------------------------------------
    function spinMainSlot(uint256 betAmount)
        external
        returns (uint8[3] memory reels, uint256 payout)
    {
        require(
            betAmount == 50 || betAmount == 100 || betAmount == 250 || betAmount == 500,
            "Invalid bet amount"
        );

        _burn(msg.sender, betAmount);

        uint256 rand = _random(betAmount);
        reels[0] = _randomSymbol(rand, 0);
        reels[1] = _randomSymbol(rand, 1);
        reels[2] = _randomSymbol(rand, 2);

        payout = _calculatePayout(reels, betAmount);

        uint256 multiplier = activeMultiplier[msg.sender];
        if (payout > 0 && multiplier > 1) {
            payout = payout * multiplier;
            activeMultiplier[msg.sender] = 0;
        }

        _mint(msg.sender, payout);

        if (chargeMeter[msg.sender] < CHARGE_METER_MAX) {
            chargeMeter[msg.sender] += 1;
        }

        bytes32 simulatedHash = keccak256(
            abi.encodePacked(rand, reels[0], reels[1], reels[2], payout, block.timestamp)
        );

        emit SpinResult(msg.sender, reels, betAmount, payout, block.timestamp, simulatedHash);

        if (payout >= betAmount * 100) {
            emit SuperMegaWin(msg.sender, payout, payout / betAmount, 5, block.timestamp);
        }
    }

    function _calculatePayout(uint8[3] memory reels, uint256 betAmount)
        private
        pure
        returns (uint256)
    {
        // Three of a kind
        if (reels[0] == reels[1] && reels[1] == reels[2] && reels[0] != NONE) {
            if (reels[0] == BITCOIN) return betAmount * 500;
            if (reels[0] == SEVEN) return betAmount * 200;
            if (reels[0] == DIAMOND) return betAmount * 100;
            if (reels[0] == ETHEREUM) return betAmount * 50;
        }

        // Any matching pair of non-blank symbols
        bool pair = (reels[0] == reels[1] && reels[0] != NONE) ||
            (reels[1] == reels[2] && reels[1] != NONE) ||
            (reels[0] == reels[2] && reels[0] != NONE);

        if (pair) {
            return betAmount * 5;
        }

        return 0;
    }

    // ---------------------------------------------------------------------
    // Bonus Vault (scatter hunt + charge meter)
    // ---------------------------------------------------------------------
    function spinBonusVault()
        external
        returns (bool scatterHit, uint256 payout)
    {
        _burn(msg.sender, BONUS_VAULT_COST);

        uint256 rand = _random(BONUS_VAULT_COST);

        uint8 scatterCount = 0;
        for (uint8 i = 0; i < 3; i++) {
            if (uint256(keccak256(abi.encodePacked(rand, i))) % 10 == 0) {
                // ~10% chance per reel
                scatterCount++;
            }
        }

        scatterHit = scatterCount == 3;

        if (scatterHit) {
            payout = BONUS_VAULT_COST * 50;
            _mint(msg.sender, payout);
            chargeMeter[msg.sender] = 0;
        } else {
            payout = 0;
            if (chargeMeter[msg.sender] < CHARGE_METER_MAX) {
                chargeMeter[msg.sender] += 1;
            }
            if (chargeMeter[msg.sender] >= CHARGE_METER_MAX) {
                chargeMeter[msg.sender] = 0;
                wheelSpinsAvailable[msg.sender] += 1;
            }
        }

        bytes32 simulatedHash = keccak256(
            abi.encodePacked(rand, scatterCount, payout, block.timestamp)
        );

        emit BonusVaultResult(
            msg.sender,
            scatterHit,
            payout,
            chargeMeter[msg.sender],
            block.timestamp,
            simulatedHash
        );
    }

    // ---------------------------------------------------------------------
    // Wheel of Satoshi (unlocked once the charge meter fills)
    // ---------------------------------------------------------------------
    function spinWheelOfSatoshi()
        external
        returns (string memory prizeType, uint256 amount)
    {
        require(wheelSpinsAvailable[msg.sender] > 0, "No wheel spins available");
        wheelSpinsAvailable[msg.sender] -= 1;

        uint256 rand = _random(1);
        uint256 r = rand % 100;

        if (r < 5) {
            prizeType = "JACKPOT";
            amount = 10000;
            _mint(msg.sender, amount);
        } else if (r < 30) {
            prizeType = "MULTIPLIER_2X";
            amount = 2;
            activeMultiplier[msg.sender] = 2;
        } else if (r < 70) {
            prizeType = "MYSTERY_BOX";
            amount = 500 + ((rand >> 8) % 1500);
            _mint(msg.sender, amount);
        } else {
            prizeType = "EXTRA_SPIN";
            amount = 1;
            wheelSpinsAvailable[msg.sender] += 1;
        }

        bytes32 simulatedHash = keccak256(
            abi.encodePacked(rand, prizeType, amount, block.timestamp)
        );

        emit WheelOfSatoshiResult(msg.sender, prizeType, amount, block.timestamp, simulatedHash);
    }

    // ---------------------------------------------------------------------
    // View helpers for the frontend
    // ---------------------------------------------------------------------
    function getPlayerState(address player)
        external
        view
        returns (
            uint256 balance,
            uint256 charge,
            uint256 wheelSpins,
            uint256 multiplier,
            bool claimedInitial
        )
    {
        balance = _balances[player];
        charge = chargeMeter[player];
        wheelSpins = wheelSpinsAvailable[player];
        multiplier = activeMultiplier[player];
        claimedInitial = hasClaimedInitialFaucet[player];
    }
}

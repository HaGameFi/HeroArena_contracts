// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract HapToken is ERC20Burnable, Ownable {
    // The time interval from each 'mint' to the 'HAP mining pool' is not less than 365 days
    uint256 public constant MINT_INTERVAL = 365 days;

    // All of the minted 'HAP' will be moved to the mainPool.
    address public mainPool;

    // The unix Timestamp for the latest mint.
    uint256 public latestMintingTime;

    // All of the minted 'HAP' burned in the corresponding mining pool if the released amount is not used up in the current year
    uint256[6] public maxMintOfYears;

    // The number of times 'mint
    uint256 public yearMint = 0;

    event MainPoolUpdated(address indexed oldPool, address indexed newPool);
    event YearlyMint(uint256 indexed year, address indexed dest, uint256 amount);
    event YearlyBurn(uint256 indexed year, address indexed pool, uint256 amount);

    constructor() ERC20("HeroArenaPlay Token", "HAP") Ownable(msg.sender) {
        maxMintOfYears[0] = 400000000 * 10 ** 18;
        maxMintOfYears[1] = 225000000 * 10 ** 18;
        maxMintOfYears[2] = 175000000 * 10 ** 18;
        maxMintOfYears[3] = 125000000 * 10 ** 18;
        maxMintOfYears[4] = 75000000  * 10 ** 18;
        maxMintOfYears[5] = 0;
    }

    /**
     * The unix Timestamp of 'mint' can be executed next time
     */
    function nextMintingTime() public view returns(uint256) {
        return latestMintingTime + MINT_INTERVAL;
    }

    /**
     * Set the target mining pool contract for minting
     */
    function setMainPool(address pool) external onlyOwner {
        require(pool != address(0));
        emit MainPoolUpdated(mainPool, pool);
        mainPool = pool;
    }

    /**
     * Distribute HAP to the main mining pool according to the HAP limit that can be released every year
     */
    function mint(address dest) external {
        require(msg.sender == mainPool, "Invalid minter");
        require(dest != address(0), "Invalid dest");
        require(nextMintingTime() < block.timestamp, "Mining not allowed yet");

        uint256 currentYear = yearMint;
        yearMint += 1;
        latestMintingTime = block.timestamp;

        // Burn unused tokens remaining in the pool from the previous year
        if (currentYear > 0) {
            uint256 remaining = balanceOf(mainPool);
            if (remaining > 0) {
                _burn(mainPool, remaining);
                emit YearlyBurn(currentYear - 1, mainPool, remaining);
            }
        }

        uint256 amountOfThisYear = currentYear < 5 ? maxMintOfYears[currentYear] : 0;
        _mint(dest, amountOfThisYear);
        emit YearlyMint(currentYear, dest, amountOfThisYear);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract WrappedStakedTONStorage {

    struct StakingTracker {
        Layer2 layer2;
        address account;
        uint256 amount;
        uint256 stakingIndex;
        uint256 depositTime;
    }

    struct Layer2 {
        address layer2Address;
        address l1StandardBridge;
        address l1CrossDomainMessenger;
        address WSTONManager;
        address l2wston;
    }

    Layer2[] public layer2s; // 0: TITAN, 1: THANOS, 2: ARBITRUM etc...
    StakingTracker[] public stakingTrackers;
    uint256 stakingTrackerCount;

    uint32 public constant MIN_DEPOSIT_GAS_LIMIT = 210000;


    address public depositManager;
    address public seigManager;
    address public l1wton;

    bool paused;

    // Main events
    event DepositedAndBridged(address indexed account, address indexed layer2, uint256 amount, uint256 stakingIndex, uint256 depositTime);
    event Deposited(uint256 indexed stakingIndex, address indexed account, uint256 amount, uint256 depositTime);
    event Transferred(uint256 indexed stakingIndex, address from, address to, uint256 amount);


    // Pause Events
    event Paused(address account);
    event Unpaused(address account);
}
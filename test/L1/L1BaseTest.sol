// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import { L1WrappedStakedTONFactory } from "../../src/L1/L1WrappedStakedTONFactory.sol";
import { L1WrappedStakedTON } from "../../src/L1/L1WrappedStakedTON.sol";
import { L1WrappedStakedTONStorage } from "../../src/L1/L1WrappedStakedTONStorage.sol";


import { DepositManager } from "../../src/L1/Mock/DepositManager.sol";
import { SeigManager } from "../../src/L1/Mock/SeigManager.sol";
import { MockToken } from "../../src/L1/Mock/MockToken.sol";
import { CoinageFactory } from "../../src/L1/Mock/CoinageFactory.sol";
import { Layer2Registry } from "../../src/L1/Mock/Layer2Registry.sol";
import { Candidate } from "../../src/L1/Mock/Candidate.sol";
import { RefactorCoinageSnapshot } from "../../src/L1/Mock/proxy/RefactorCoinageSnapshot.sol";
import { TON } from "../../src/L1/Mock/token/TON.sol";
import { WTON } from "../../src/L1/Mock/token/WTON.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract L1BaseTest is Test {
    using SafeERC20 for IERC20;

    address payable owner;
    address payable user1;
    address payable user2;
    address payable committee;

    address l1WrappedStakedTon;
    address l1wrappedstakedtonProxy;
    address l1wrappedstakedtonFactory;
    address wton;
    address ton;

    address depositManager;
    address seigManager;
    address factory;
    address layer2Registry;
    address stakingLayer2Address;
    address candidate;

    uint256 delay = 93046;
    uint256 seigPerBlock = 3920000000000000000000000000;
    uint256 lastSeigBlock = block.number;

    uint256 public constant DECIMALS = 10**27;

    event WithdrawalRequested(address indexed _to, uint256 amount);

    function setUp() public virtual {
        owner = payable(makeAddr("Owner"));
        user1 = payable(makeAddr("User1"));
        user2 = payable(makeAddr("User2"));
        committee = payable(makeAddr("Committee"));

        vm.startPrank(owner);
        vm.warp(1632934800);

        ton = address(new TON()); // 18 decimals
        wton = address(new WTON(TON(ton))); // 27 decimals
        
        // we mint 1,000,000 TON to the owner
        TON(ton).mint(owner, 1000000 * 10 ** 18);

        // Transfer 20,000 TON to user 1 and user 2
        TON(ton).transfer(user1, 20000 * 10 ** 18); 
        TON(ton).transfer(user2, 20000 * 10 ** 18); 

        // we swap 10,000 TON to WTON
        vm.startPrank(user1);
        TON(ton).approve(wton, 10000 * 10 ** 18);
        WTON(wton).swapFromTON(10000 * 10 ** 18);
        vm.stopPrank();

        vm.startPrank(user2); 
        TON(ton).approve(wton, 10000 * 10 ** 18);
        WTON(wton).swapFromTON(10000 * 10 ** 18); 
        vm.stopPrank();

        vm.startPrank(owner);
        // give ETH to User1 to cover gasFees associated with using VRF functions
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        depositManager = address(new DepositManager());
        seigManager = address(new SeigManager());
        factory = address(new CoinageFactory());
        layer2Registry = address(new Layer2Registry());
        candidate = address(new Candidate());

        DepositManager(depositManager).initialize(
            wton,
            layer2Registry,
            seigManager,
            delay
        );

        SeigManager(seigManager).initialize(
            ton,
            wton,
            layer2Registry,
            depositManager,
            seigPerBlock,
            factory,
            lastSeigBlock
        );

        Candidate(candidate).initialize(
            owner,
            true,
            "",
            committee,
            seigManager
        );

        require(Layer2Registry(layer2Registry).registerAndDeployCoinage(candidate, seigManager));

        l1wrappedstakedtonFactory = address(new L1WrappedStakedTONFactory());
        l1WrappedStakedTon = address(new L1WrappedStakedTON());
        L1WrappedStakedTONFactory(l1wrappedstakedtonFactory).initialize(wton, ton);
        L1WrappedStakedTONFactory(l1wrappedstakedtonFactory).setWstonImplementation(l1WrappedStakedTon);

        
        DepositManager(depositManager).setSeigManager(seigManager);

        // deploy and initialize Wrapped Staked TON
        l1wrappedstakedtonProxy = address(L1WrappedStakedTONFactory(l1wrappedstakedtonFactory).createWSTONToken(
            candidate,
            depositManager,
            seigManager,
            "Titan Wrapped Staked TON",
            "Titan WSTON"
        ));

        vm.stopPrank();

        vm.startPrank(l1wrappedstakedtonProxy);
        IERC20(ton).approve(wton, type(uint256).max);
        vm.stopPrank();
        //end of setup
    }


    function testSetup() public view {
        address l1wtonCheck = L1WrappedStakedTON(l1wrappedstakedtonProxy).depositManager();
        assert(l1wtonCheck == depositManager);

        address seigManagerCheck =  L1WrappedStakedTON(l1wrappedstakedtonProxy).seigManager();
        assert(seigManagerCheck == seigManager);

    }
}

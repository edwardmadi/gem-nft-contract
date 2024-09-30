// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IGemFactory } from "../interfaces/IGemFactory.sol";
import { GemFactoryStorage } from "./GemFactoryStorage.sol";  
import {AuthControl} from "../common/AuthControl.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { RandomPackStorage } from "./RandomPackStorage.sol";
import "../proxy/ProxyStorage.sol";

import {DRBConsumerBase} from "./Randomness/DRBConsumerBase.sol";
import {IDRBCoordinator} from "../interfaces/IDRBCoordinator.sol";

interface ITreasury {
    function transferWSTON(address _to, uint256 _amount) external returns(bool);
    function transferTreasuryGEMto(address _to, uint256 _tokenId) external returns(bool);
    function getWSTONBalance() external view returns (uint256);
    function createPreminedGEM( 
        GemFactoryStorage.Rarity _rarity,
        uint8[2] memory _color, 
        uint8[4] memory _quadrants,  
        string memory _tokenURI
    ) external returns (uint256);
}

contract RandomPack is ProxyStorage, ReentrancyGuard, IERC721Receiver, AuthControl, DRBConsumerBase, RandomPackStorage {
    using SafeERC20 for IERC20;

    modifier whenNotPaused() {
      require(!paused, "Pausable: paused");
      _;
    }

    modifier whenPaused() {
        require(paused, "Pausable: not paused");
        _;
    }

    constructor(
        address coordinator,  
        address _ton, 
        address _gemFactory, 
        address _treasury, 
        uint256 _randomPackFees
    ) DRBConsumerBase(coordinator) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        gemFactory = _gemFactory;
        treasury = _treasury;
        ton = _ton;
        drbcoordinator = coordinator;
        randomPackFees = _randomPackFees;
        callbackGasLimit = 600000;
        perfectCommonGemURI = "";
    }


    function setGemFactory(address _gemFactory) external onlyOwner {
        if(gemFactory == address(0)) {
            revert InvalidAddress();
        }
        gemFactory = _gemFactory;
    }

    function setRandomPackFees(uint256 _randomPackFees) external onlyOwner {
        if(randomPackFees == 0) {
            revert RandomPackFeesEqualToZero();
        }
        randomPackFees = _randomPackFees;
    }

    function setTreasury(address _treasury) external onlyOwner {
        if(_treasury == address(0)) {
            revert InvalidAddress();
        }
        treasury = _treasury;
    }

    function setPerfectCommonGemURI(string memory _tokenURI) external onlyOwner {
        perfectCommonGemURI = _tokenURI;
    }

    function setCallbackGasLimit(uint32 _callbackGasLimit) external onlyOwner {
        callbackGasLimit = _callbackGasLimit;
    }

    function requestRandomGem() external payable whenNotPaused nonReentrant returns(uint256) {
        if(msg.sender == address(0)) {
            revert InvalidAddress();
        }
        //users pays upfront fees
        //user must approve the contract for the fees amount before calling the function
        IERC20(ton).safeTransferFrom(msg.sender, address(this), randomPackFees);
        
        // defining the random value
        uint256 requestId = requestRandomness(0,0,callbackGasLimit);        

        s_requests[requestId].requested = true;
        s_requests[requestId].requester = msg.sender;
        unchecked {
            requestCount++;
        }

        //IDRBCoordinator(drbcoordinator).fulfillRandomness(requestId);

        return requestId;
    }

    // Implement the abstract function from DRBConsumerBase
    function fulfillRandomWords(uint256 requestId, uint256 randomNumber) internal override {
        if(!s_requests[requestId].requested) {
            revert RequestNotMade();
        }
        s_requests[requestId].fulfilled = true;
        s_requests[requestId].randomWord = randomNumber;

        (uint256 gemCount, uint256[] memory tokenIds) = IGemFactory(gemFactory).getGemListAvailableForRandomPack();

        if(gemCount > 0) {
            // same calculation as for the mining process
            uint256 modNbGemsAvailable = (randomNumber % gemCount);
            s_requests[requestId].chosenTokenId = tokenIds[modNbGemsAvailable];
            // transfer the gem from the treasury to the user.
            ITreasury(treasury).transferTreasuryGEMto(s_requests[requestId].requester, s_requests[requestId].chosenTokenId);
            emit RandomGemTransferred(s_requests[requestId].chosenTokenId, s_requests[requestId].requester);
        } else {
            // if there is no gem available in the pool, we mint a new perfect common gem. note that it reverts if the treasury does not have enough WSTON.
            s_requests[requestId].chosenTokenId = ITreasury(treasury).createPreminedGEM(GemFactoryStorage.Rarity.COMMON, [0,0], [1,1,1,1], "");
            ITreasury(treasury).transferTreasuryGEMto(msg.sender, s_requests[requestId].chosenTokenId);
            emit CommonGemMinted();
        }
    }

    // onERC721Received function to accept ERC721 tokens
    function onERC721Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes calldata /*data*/
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

}
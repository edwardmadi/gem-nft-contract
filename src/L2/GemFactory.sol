// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {DRBConsumerBase} from "./Randomness/DRBConsumerBase.sol";
import {GemFactoryStorage} from "./GemFactoryStorage.sol";
import {IDRBCoordinator} from "../interfaces/IDRBCoordinator.sol";
import { GemLibrary } from "../libraries/GemLibrary.sol";
import { MiningLibrary } from "../libraries/MiningLibrary.sol";
import { ForgeLibrary } from "../libraries/ForgeLibrary.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../proxy/ProxyStorage.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ITreasury {
    function transferWSTON(address _to, uint256 _amount) external returns(bool);
    function transferTreasuryGEMto(address _to, uint256 _tokenId) external returns(bool);
}

/**
 * @title GemFactory
 * @author TOKAMAK OPAL TEAM
 * @dev The GemFactory contract is responsible for managing the lifecycle of GEM tokens within the system.
 * This includes the creation, mining, forging, and melting of GEMs. The contract provides functionalities
 * for both administrative and user interactions, ensuring a comprehensive management of GEM tokens.
 *
 * Administrative Functions
 * - Premine GEMs: Allows administrators to create and allocate GEMs directly to the treasury contract.
 *   This is useful for initializing the system with a predefined set of GEMs that can be distributed or sold later.
 *
 * User Functions
 * - Mine GEMs: Users can engage in mining activities to acquire new GEMs. The mining process is governed
 *   by specific rules and cooldown periods, ensuring a fair and balanced distribution of GEMs.
 * - Forge GEMs: Users have the ability to combine multiple GEMs of the same rarity to create a new, potentially
 *   more valuable GEM. This process involves burning the original GEMs and minting a new one.
 * - Melt GEMs: Users can convert their GEMs back into their underlying value, effectively "melting" the GEM.
 *   This process involves burning the GEM token and transferring its value to the user.
 *
 * Security and Access Control
 * - The contract implements access control mechanisms to ensure that only authorized users can perform certain actions.
 *   For example, only the contract owner or designated administrators can premine GEMs.
 * - The contract also includes mechanisms to pause and unpause operations, providing an additional layer of security
 *   in case of emergencies or required maintenance.
 *
 * Integration
 * - The GemFactory contract integrates with other components of the system, such as the treasury and marketplace contracts,
 *   to facilitate seamless interactions and transactions involving GEMs.
 */
contract GemFactory is ProxyStorage, Initializable, ERC721URIStorageUpgradeable, GemFactoryStorage, OwnableUpgradeable, DRBConsumerBase, ReentrancyGuard {

    using SafeERC20 for IERC20;
    using GemLibrary for GemFactoryStorage.Gem[];
    using MiningLibrary for GemFactoryStorage.Gem[];
    using ForgeLibrary for GemFactoryStorage.Gem[];

    /**
     * @notice Modifier to ensure the contract is not paused.
     */
    modifier whenNotPaused() {
      require(!paused, "Pausable: paused");
      _;
    }

    /**
     * @notice Modifier to ensure the contract is paused.
     */
    modifier whenPaused() {
        require(paused, "Pausable: not paused");
        _;
    }

    /**
     * @notice Modifier to ensure the caller is the treasury contract
     */
    modifier onlyTreasury() {
        require(
            msg.sender == treasury,
            "function callable from treasury contract only"
        );
        _;
    }

    /**
     * @notice Modifier to ensure the caller is either the airdrop or the marketplace contract
     */
    modifier onlyMarketPlaceOrAirdrop() {
        require(
            msg.sender == airdrop ||
            msg.sender == marketplace, 
            "function callable from the marketplace or airdrop contracts only"
        );
        _;
    }

    /**
     * @notice Pauses the contract, preventing certain actions.
     * @dev Only callable by the owner when the contract is not paused.
     */
    function pause() public onlyOwner whenNotPaused {
        paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @notice Unpauses the contract, allowing actions to be performed.
     * @dev Only callable by the owner when the contract is paused.
     */
    function unpause() public onlyOwner whenNotPaused {
        paused = false;
        emit Unpaused(msg.sender);
    }

    //---------------------------------------------------------------------------------------
    //--------------------------INITIALIZATION FUNCTIONS-------------------------------------
    //---------------------------------------------------------------------------------------

    /**
     * @notice Initializes the contract with the given parameters.
     * @param _coordinator Address of the randomness coordinator.
     * @param _owner Address of the contract owner.
     * @param _wston Address of the WSTON token.
     * @param _ton Address of the TON token.
     * @param _treasury Address of the treasury contract.
     */
    function initialize(
        address _coordinator,
        address _owner,
        address _wston, 
        address _ton,
        address _treasury  
    ) external initializer {
        __ERC721_init("GemSTON", "GEM");
        __DRBConsumerBase_init(_coordinator);
        __Ownable_init(_owner);
        wston = _wston;
        ton = _ton;
        treasury = _treasury;
    }

    /**
     * @notice Sets the mining periods for different gem rarities.
     * @param _RareGemsMiningPeriod Mining period for rare gems.
     * @param _UniqueGemsMiningPeriod Mining period for unique gems.
     * @param _EpicGemsMiningPeriod Mining period for epic gems.
     * @param _LegendaryGemsMiningPeriod Mining period for legendary gems.
     * @param _MythicGemsMiningPeriod Mining period for mythic gems.
     */
    function setGemsMiningPeriods(
        uint32 _RareGemsMiningPeriod,
        uint32 _UniqueGemsMiningPeriod,
        uint32 _EpicGemsMiningPeriod,
        uint32 _LegendaryGemsMiningPeriod,
        uint32 _MythicGemsMiningPeriod
    ) external onlyOwner {
        RareGemsMiningPeriod = _RareGemsMiningPeriod;
        UniqueGemsMiningPeriod = _UniqueGemsMiningPeriod;
        EpicGemsMiningPeriod = _EpicGemsMiningPeriod;
        LegendaryGemsMiningPeriod = _LegendaryGemsMiningPeriod;
        MythicGemsMiningPeriod = _MythicGemsMiningPeriod;

        emit GemsMiningPeriodModified(
            _RareGemsMiningPeriod,
            _UniqueGemsMiningPeriod,
            _EpicGemsMiningPeriod,
            _LegendaryGemsMiningPeriod,
            _MythicGemsMiningPeriod
        );
    }

    /**
     * @notice Sets the cooldown periods for different gem rarities.
     * @param _RareGemsCooldownPeriod Cooldown period for rare gems.
     * @param _UniqueGemsCooldownPeriod Cooldown period for unique gems.
     * @param _EpicGemsCooldownPeriod Cooldown period for epic gems.
     * @param _LegendaryGemsCooldownPeriod Cooldown period for legendary gems.
     * @param _MythicGemsCooldownPeriod Cooldown period for mythic gems.
     */
    function setGemsCooldownPeriods(
        uint32 _RareGemsCooldownPeriod,
        uint32 _UniqueGemsCooldownPeriod,
        uint32 _EpicGemsCooldownPeriod,
        uint32 _LegendaryGemsCooldownPeriod,
        uint32 _MythicGemsCooldownPeriod
    ) external onlyOwner {
        RareGemsCooldownPeriod = _RareGemsCooldownPeriod;
        UniqueGemsCooldownPeriod = _UniqueGemsCooldownPeriod;
        EpicGemsCooldownPeriod = _EpicGemsCooldownPeriod;
        LegendaryGemsCooldownPeriod = _LegendaryGemsCooldownPeriod;
        MythicGemsCooldownPeriod = _MythicGemsCooldownPeriod;
        
        emit GemsCoolDownPeriodModified( 
            RareGemsCooldownPeriod, 
            UniqueGemsCooldownPeriod, 
            EpicGemsCooldownPeriod, 
            LegendaryGemsCooldownPeriod, 
            MythicGemsCooldownPeriod
        );
    }

    /**
     * @notice Sets the number of mining attempts for different gem rarities.
     * @param _RareminingTry Number of mining attempts for rare gems.
     * @param _UniqueminingTry Number of mining attempts for unique gems.
     * @param _EpicminingTry Number of mining attempts for epic gems.
     * @param _LegendaryminingTry Number of mining attempts for legendary gems.
     * @param _MythicminingTry Number of mining attempts for mythic gems.
     */
    function setMiningTries(
        uint8 _RareminingTry,
        uint8 _UniqueminingTry,
        uint8 _EpicminingTry,
        uint8 _LegendaryminingTry,
        uint8 _MythicminingTry
    ) external onlyOwner {
        RareminingTry = _RareminingTry;
        UniqueminingTry = _UniqueminingTry;
        EpicminingTry = _EpicminingTry;
        LegendaryminingTry = _LegendaryminingTry;
        MythicminingTry = _MythicminingTry;

        emit GemsMiningTryModified(
            _RareminingTry,
            _UniqueminingTry,
            _EpicminingTry,
            _LegendaryminingTry,
            _MythicminingTry
        );
    }

    /**
     * @notice Sets the value of different gem rarities.
     * @param _CommonGemsValue Value of common gems.
     * @param _RareGemsValue Value of rare gems.
     * @param _UniqueGemsValue Value of unique gems.
     * @param _EpicGemsValue Value of epic gems.
     * @param _LegendaryGemsValue Value of legendary gems.
     * @param _MythicGemsValue Value of mythic gems.
     */
    function setGemsValue(
        uint256 _CommonGemsValue,
        uint256 _RareGemsValue,
        uint256 _UniqueGemsValue,
        uint256 _EpicGemsValue,
        uint256 _LegendaryGemsValue,
        uint256 _MythicGemsValue
    ) external onlyOwner {
        CommonGemsValue = _CommonGemsValue;
        RareGemsValue = _RareGemsValue;
        UniqueGemsValue = _UniqueGemsValue;
        EpicGemsValue = _EpicGemsValue;
        LegendaryGemsValue = _LegendaryGemsValue;
        MythicGemsValue = _MythicGemsValue;

        emit GemsValueModified(
            _CommonGemsValue,
            _RareGemsValue,
            _UniqueGemsValue,
            _EpicGemsValue,
            _LegendaryGemsValue,
            _MythicGemsValue
        );
    }

    /**
     * @notice Sets the treasury address.
     * @param _treasury The new treasury address.
     */
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    /**
     * @notice Sets the marketplace address.
     * @param _marketplace The new marketplace address.
     */
    function setMarketPlaceAddress(address _marketplace) external onlyOwner {
        marketplace = _marketplace;
    }

    /**
     * @notice Sets the airdrop address.
     * @param _airdrop The new airdrop address.
     */
    function setAirdrop(address _airdrop) external onlyOwner {
        airdrop = _airdrop;
    }

    //---------------------------------------------------------------------------------------
    //--------------------------EXTERNAL FUNCTIONS-------------------------------------------
    //---------------------------------------------------------------------------------------

    /**
     * @notice function that allow users to forge their gems. Gems must have the same rarity. 
     * Users can choose the color the forged gem will have if it respects specific conditions. 
     * old gems are burnt while the new forged gem is minted.
     * @param _tokenIds array of tokens to be forged. Must respect some length depending on the rarity chosen
     * @param _rarity to check if the rarity of each token selected is the same
     * @param _color color desired of the forged gem
     */
    function forgeTokens(
        uint256[] memory _tokenIds,
        Rarity _rarity,
        uint8[2] memory _color
    ) external whenNotPaused returns (uint256 newGemId) {
        // Define ForgeParams struct with predefined values for various GEM types
        ForgeLibrary.ForgeParams memory params = ForgeLibrary.ForgeParams({
            RareGemsValue: RareGemsValue,
            UniqueGemsValue: UniqueGemsValue,
            EpicGemsValue: EpicGemsValue,
            LegendaryGemsValue: LegendaryGemsValue,
            MythicGemsValue: MythicGemsValue,
            RareGemsMiningPeriod: RareGemsMiningPeriod,
            UniqueGemsMiningPeriod: UniqueGemsMiningPeriod,
            EpicGemsMiningPeriod: EpicGemsMiningPeriod,
            LegendaryGemsMiningPeriod: LegendaryGemsMiningPeriod,
            MythicGemsMiningPeriod: MythicGemsMiningPeriod,
            RareminingTry: RareminingTry,
            UniqueminingTry: UniqueminingTry,
            EpicminingTry: EpicminingTry,
            LegendaryminingTry: LegendaryminingTry,
            MythicminingTry: MythicminingTry,
            RareGemsCooldownPeriod: RareGemsCooldownPeriod,
            UniqueGemsCooldownPeriod: UniqueGemsCooldownPeriod,
            EpicGemsCooldownPeriod: EpicGemsCooldownPeriod,
            LegendaryGemsCooldownPeriod: LegendaryGemsCooldownPeriod,
            MythicGemsCooldownPeriod: MythicGemsCooldownPeriod
        });

        // Initialize variables for forged GEM properties
        uint8[4] memory forgedQuadrants;
        Rarity newRarity;
        uint32 forgedGemsMiningPeriod;
        uint32 forgedGemsCooldownPeriod;
        uint8 forgedGemsminingTry;
        uint256 forgedGemsValue;

        // Call the forgeTokens function from Gems contract
        (newGemId, forgedQuadrants, newRarity, forgedGemsValue, forgedGemsMiningPeriod, forgedGemsCooldownPeriod, forgedGemsminingTry) = Gems.forgeTokens(
            GEMIndexToOwner,
            ownershipTokenCount,
            msg.sender,
            _tokenIds,
            _rarity,
            _color,
            params
        );

        // Emit an event for the forged GEM
        emit GemForged(msg.sender, _tokenIds, newGemId, newRarity, forgedQuadrants, _color, forgedGemsValue);

        // Burn the old tokens
        burnTokens(msg.sender, _tokenIds);

        // Mint the new token
        _safeMint(msg.sender, newGemId);
        _setTokenURI(newGemId, ""); // Set empty URI for the new token

        // Emit another event for the created GEM
        emit Created(newGemId, newRarity, _color, forgedGemsValue, forgedQuadrants, forgedGemsMiningPeriod, forgedGemsCooldownPeriod, "", msg.sender);

        return newGemId;
    }

    /**
     * @notice triggers the mining process of a gem by the function caller
     * @param _tokenId Id of the token to be mined.
     * @return true if the gem user started mining the gem
     * @dev the Gem must be Rare or above
     * @dev the cooldown period must have elapsed
     * @dev the Gem must not be locked. Therefore, it must not be listed on the marketplace 
     * @dev There must be more than 1 mining try left
     */
    function startMiningGEM(uint256 _tokenId) external whenNotPaused returns (bool) {
        // Ensure the caller's address is not zero
        if (msg.sender == address(0)) {
            revert AddressZero();
        }
        // Ensure the caller is the owner of the GEM
        if (ownerOf(_tokenId) != msg.sender) {
            revert NotGemOwner();
        }
        // Ensure the cooldown period for the GEM has elapsed
        if (Gems[_tokenId].gemCooldownPeriod > block.timestamp) {
            revert CooldownPeriodNotElapsed();
        }
        // Ensure the GEM is not currently locked
        if (Gems[_tokenId].isLocked) {
            revert GemIsLocked();
        }
        // Ensure the GEM's rarity is not COMMON, as COMMON gems cannot be mined
        if (Gems[_tokenId].rarity == Rarity.COMMON) {
            revert WrongRarity();
        }
        // Ensure there are mining attempts left for the GEM
        if (Gems[_tokenId].miningTry == 0) {
            revert NoMiningTryLeft();
        }

        // Modify storage variables to start the mining process
        Gems.startMining(userMiningToken, userMiningStartTime, msg.sender, _tokenId);

        // Emit an event indicating that mining has started
        emit GemMiningStarted(_tokenId, msg.sender, block.timestamp, Gems[_tokenId].miningTry);
        return true;
    }

    /**
     * @notice function that cancels the mining process. note that the mining attempt spent is not recovered
     * @param _tokenId the id of the token that is mining
     * @dev the user must be the owner of the token
     * @dev the user must be mining this token.
     * @dev the user must not have already called pickMinedGem function
     */
    function cancelMining(uint256 _tokenId) external whenNotPaused returns (bool) {
        // Ensure the caller is the owner of the GEM
        if (GEMIndexToOwner[_tokenId] != msg.sender) {
            revert NotGemOwner();
        }
        // Ensure the GEM is currently locked, indicating it is in the mining process
        if (Gems[_tokenId].isLocked != true) {
            revert GemIsNotLocked();
        }
        // Ensure the GEM is currently being mined by the user
        if (userMiningToken[msg.sender][_tokenId] != true) {
            revert NotMining();
        }
        // Ensure the GEM has not already been picked (randomness request not initiated)
        if (Gems[_tokenId].randomRequestId != 0) {
            revert GemAlreadyPicked();
        }

        // Modify the storage variables associated with the mining process to cancel it
        Gems.cancelMining(userMiningToken, userMiningStartTime, msg.sender, _tokenId);

        // Emit an event indicating that mining has been canceled
        emit MiningCancelled(_tokenId, msg.sender, block.timestamp);
        return true;
    }

    /**
     * @notice Picks a mined gem after the mining period has elapsed.
     * @param _tokenId ID of the token to pick.
     * @return requestId The request ID for randomness.
     * @dev user pays msg.value and get back the excess ETH that is not spent on gas by the node
     */
    function pickMinedGEM(uint256 _tokenId) external payable whenNotPaused nonReentrant returns (uint256) {
        // Ensure the caller is the owner of the GEM
        if (ownerOf(_tokenId) != msg.sender) {
            revert NotGemOwner();
        }
        // Ensure the mining period has elapsed
        if (block.timestamp < userMiningStartTime[msg.sender][_tokenId] + Gems[_tokenId].miningPeriod) {
            revert MiningPeriodNotElapsed();
        }
        // Ensure the GEM is currently locked
        if (Gems[_tokenId].isLocked == false) {
            revert GemIsNotLocked();
        }
        // Ensure the GEM is currently being mined
        if (userMiningToken[ownerOf(_tokenId)][_tokenId] != true) {
            revert NotMining();
        }

        // Request randomness from the consumer with default parameters
        (uint256 directFundingCost, uint256 requestId) = requestRandomness(0, 0, CALLBACK_GAS_LIMIT);
        // Store the request ID in the GEM's data
        Gems[_tokenId].randomRequestId = requestId;

        // Update the request mapping with details of the request
        s_requests[requestId].tokenId = _tokenId;
        s_requests[requestId].requested = true;
        s_requests[requestId].requester = msg.sender;
        unchecked {
            // Increment the request count
            requestCount++;
        }

        // Refund excess ETH to the user if they overpaid
        if (msg.value > directFundingCost) {
            (bool success, ) = msg.sender.call{value: msg.value - directFundingCost}("");
            if (!success) {
                revert FailedToSendEthBack();
            }
            // Emit an event for the ETH refund
            emit EthSentBack(msg.value - directFundingCost);
        }

        // Emit an event for the random GEM request
        emit RandomGemRequested(_tokenId, Gems[_tokenId].randomRequestId);
        return requestId;
    }

    /**
     * @notice Melts a gem, converting it back to its value.
     * @param _tokenId ID of the token to melt.
     * @dev The caller receives the WSTON amount associated with the GEM.
     * @dev The ERC721 token is burned.
     * @dev The caller must be the token owner.
     */
    function meltGEM(uint256 _tokenId) external whenNotPaused {
        // Check if the caller's address is zero
        if (msg.sender == address(0)) {
            revert AddressZero();
        }
        // Ensure the caller is the owner of the GEM
        if (GEMIndexToOwner[_tokenId] != msg.sender) {
            revert NotGemOwner();
        }
        // Get the value of the GEM
        uint256 amount = Gems[_tokenId].value;
        // Burn the GEM and update ownership counts
        Gems.burnGem(GEMIndexToOwner, ownershipTokenCount, msg.sender, _tokenId);
        // Burn the ERC721 token
        _burn(_tokenId);
        // Transfer the WSTON amount to the caller
        if (!ITreasury(treasury).transferWSTON(msg.sender, amount)) {
            revert TransferFailed();
        }
        // Emit an event indicating the GEM has been melted
        emit GemMelted(_tokenId, msg.sender);
    }

    /**
     * @notice Creates a premined pool of GEM based on their attributes passed in the parameters and assigns their ownership to the contract.
     * @param _rarity The rarity of the GEM to be created.
     * @param _color The colors of the GEM to be created.
     * @param _quadrants Quadrants of the GEM to be created.
     * @param _tokenURI TokenURIs of each GEM.
     * @return The IDs of the newly created GEM.
     */
    function createGEM(
        Rarity _rarity,
        uint8[2] memory _color,
        uint8[4] memory _quadrants,
        string memory _tokenURI
    ) public onlyTreasury whenNotPaused returns (uint256) {
        
        // Check if the specified color combination exists
        if (!colorExists(_color[0], _color[1])) {
            revert ColorNotExist();
        }        
        
        // Declare variables for GEM attributes
        uint32 _gemCooldownPeriod;
        uint32 _miningPeriod;
        uint256 _value;
        uint8 _miningTry;

        // Calculate the sum of the quadrant values
        uint8 sumOfQuadrants = _quadrants[0] + _quadrants[1] + _quadrants[2] + _quadrants[3];

        // Determine GEM attributes based on its rarity
        if (_rarity == Rarity.COMMON) {
            // Validate quadrant values for COMMON rarity
            if (_quadrants[0] != 1 && _quadrants[0] != 2) revert NewGemInvalidQuadrant(0, 1, 2);
            if (_quadrants[1] != 1 && _quadrants[1] != 2) revert NewGemInvalidQuadrant(1, 1, 2);
            if (_quadrants[2] != 1 && _quadrants[2] != 2) revert NewGemInvalidQuadrant(2, 1, 2);
            if (_quadrants[3] != 1 && _quadrants[3] != 2) revert NewGemInvalidQuadrant(3, 1, 2);
            if (sumOfQuadrants >= 8) revert SumOfQuadrantsTooHigh(sumOfQuadrants, "COMMON");

            // Set attributes for COMMON rarity
            _gemCooldownPeriod = 0;
            _miningPeriod = 0;
            _value = CommonGemsValue;
            _miningTry = 0;
        } else if (_rarity == Rarity.RARE) {
            // Validate quadrant values for RARE rarity
            if (_quadrants[0] != 2 && _quadrants[0] != 3) revert NewGemInvalidQuadrant(0, 2, 3);
            if (_quadrants[1] != 2 && _quadrants[1] != 3) revert NewGemInvalidQuadrant(1, 2, 3);
            if (_quadrants[2] != 2 && _quadrants[2] != 3) revert NewGemInvalidQuadrant(2, 2, 3);
            if (_quadrants[3] != 2 && _quadrants[3] != 3) revert NewGemInvalidQuadrant(3, 2, 3);
            if (sumOfQuadrants >= 12) revert SumOfQuadrantsTooHigh(sumOfQuadrants, "RARE");
            
            // Set attributes for RARE rarity
            _gemCooldownPeriod = RareGemsCooldownPeriod;
            _miningPeriod = RareGemsMiningPeriod;
            _value = RareGemsValue;
            _miningTry = RareminingTry;
        } else if (_rarity == Rarity.UNIQUE) {
            // Validate quadrant values for UNIQUE rarity
            if (_quadrants[0] != 3 && _quadrants[0] != 4) revert NewGemInvalidQuadrant(0, 3, 4);
            if (_quadrants[1] != 3 && _quadrants[1] != 4) revert NewGemInvalidQuadrant(1, 3, 4);
            if (_quadrants[2] != 3 && _quadrants[2] != 4) revert NewGemInvalidQuadrant(2, 3, 4);
            if (_quadrants[3] != 3 && _quadrants[3] != 4) revert NewGemInvalidQuadrant(3, 3, 4);
            if (sumOfQuadrants >= 16) revert SumOfQuadrantsTooHigh(sumOfQuadrants, "UNIQUE");

            // Set attributes for UNIQUE rarity
            _gemCooldownPeriod = UniqueGemsCooldownPeriod;
            _miningPeriod = UniqueGemsMiningPeriod;
            _value = UniqueGemsValue;
            _miningTry = UniqueminingTry;
        } else if (_rarity == Rarity.EPIC) {
            // Validate quadrant values for EPIC rarity
            if (_quadrants[0] != 4 && _quadrants[0] != 5) revert NewGemInvalidQuadrant(0, 4, 5);
            if (_quadrants[1] != 4 && _quadrants[1] != 5) revert NewGemInvalidQuadrant(1, 4, 5);
            if (_quadrants[2] != 4 && _quadrants[2] != 5) revert NewGemInvalidQuadrant(2, 4, 5);
            if (_quadrants[3] != 4 && _quadrants[3] != 5) revert NewGemInvalidQuadrant(3, 4, 5);
            if (sumOfQuadrants >= 20) revert SumOfQuadrantsTooHigh(sumOfQuadrants, "EPIC");
            
            // Set attributes for EPIC rarity
            _gemCooldownPeriod = EpicGemsCooldownPeriod;
            _miningPeriod = EpicGemsMiningPeriod;
            _value = EpicGemsValue;
            _miningTry = EpicminingTry;
        } else if (_rarity == Rarity.LEGENDARY) {
            // Validate quadrant values for LEGENDARY rarity
            if (_quadrants[0] != 5 && _quadrants[0] != 6) revert NewGemInvalidQuadrant(0, 5, 6);
            if (_quadrants[1] != 5 && _quadrants[1] != 6) revert NewGemInvalidQuadrant(1, 5, 6);
            if (_quadrants[2] != 5 && _quadrants[2] != 6) revert NewGemInvalidQuadrant(2, 5, 6);
            if (_quadrants[3] != 5 && _quadrants[3] != 6) revert NewGemInvalidQuadrant(3, 5, 6);
            if (sumOfQuadrants >= 24) revert SumOfQuadrantsTooHigh(sumOfQuadrants, "LEGENDARY");

            // Set attributes for LEGENDARY rarity
            _gemCooldownPeriod = LegendaryGemsCooldownPeriod;
            _miningPeriod = LegendaryGemsMiningPeriod;
            _value = LegendaryGemsValue;
            _miningTry = LegendaryminingTry;
        } else if (_rarity == Rarity.MYTHIC) {
            // Validate quadrant values for MYTHIC rarity
            if (_quadrants[0] != 6 || _quadrants[1] != 6 || _quadrants[2] != 6 || _quadrants[3] != 6) {
                revert NewGemInvalidQuadrant(0, 6, 6);
            }
            // Set attributes for MYTHIC rarity
            _gemCooldownPeriod = MythicGemsCooldownPeriod;
            _miningPeriod = MythicGemsMiningPeriod;
            _value = MythicGemsValue;
            _miningTry = MythicminingTry;
        } else {
            // Revert if the rarity is not recognized
            revert WrongRarity();
        }

        // Calculate the cooldown due date for the GEM
        uint256 _cooldownDueDate = block.timestamp + _gemCooldownPeriod;

        // Create the new GEM and get its ID
        uint256 newGemId = Gems.createGem(
            GEMIndexToOwner,
            ownershipTokenCount,
            msg.sender,
            _rarity,
            _color,
            _quadrants,
            _value,
            _miningPeriod,
            _cooldownDueDate,
            _miningTry,
            _tokenURI
        );

        // Mint the GEM and set its token URI
        _safeMint(msg.sender, newGemId);
        _setTokenURI(newGemId, _tokenURI);

        // Emit an event for the creation of the new GEM
        emit Created(newGemId, _rarity, _color, _value, _quadrants, _miningPeriod, _cooldownDueDate, _tokenURI, msg.sender);
        return newGemId;
    }


    /**
     * @notice Creates a premined pool of GEMs based oon their attribute passed in the parameters and assigns their ownership to the contract.
     * @param _rarities rarity of each Gem
     * @param _colors The colors of the GEMs to be created.
     * @param _quadrants quadrants of the GEMs to be created.
     * @param _tokenURIs TokenURIs of each GEM
     * @return The IDs of the newly created GEMs.
     */
    function createGEMPool(
        Rarity[] memory _rarities,
        uint8[2][] memory _colors,
        uint8[4][] memory _quadrants,
        string[] memory _tokenURIs
    ) public onlyTreasury whenNotPaused returns (uint256[] memory) {

        // Cache the length of the _rarities array for gas optimization
        uint256 length = _rarities.length;

        // Ensure all input arrays have the same length
        if (length != _colors.length || length != _quadrants.length || length != _tokenURIs.length) {
            revert MismatchedArrayLengths();
        }

        // Initialize an array to store the IDs of the newly created GEMs
        uint256[] memory newGemIds = new uint256[](_rarities.length);

        // Loop through each set of attributes and create a GEM
        for (uint256 i = 0; i < _rarities.length; ++i) {
            // Create a GEM with the specified attributes and store its ID
            newGemIds[i] = createGEM(_rarities[i], _colors[i], _quadrants[i], _tokenURIs[i]);
        }
        
        // Return the array of new GEM IDs
        return newGemIds;
    }
    
    /**
     * @notice Transfers a GEM token from one address to another.
     * @dev Overrides the ERC721 transferFrom function. The transfer is only allowed when the contract is not paused.
     *      The GEM must not be locked, and the sender and recipient must be different.
     * @param from The address to transfer the token from.
     * @param to The address to transfer the token to.
     * @param tokenId The ID of the token to transfer.
     */
    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721Upgradeable, IERC721) whenNotPaused {
        // Check if the sender and recipient addresses are the same
        if(to == from) {
            revert SameSenderAndRecipient(); // Revert if they are the same
        }

        // Check if the GEM is locked
        if(Gems[tokenId].isLocked) {
            revert GemIsLocked(); // Revert if the GEM is locked
        }

        // Perform the GEM transfer logic
        _transferGEM(from, to, tokenId);

        // Call the parent contract's transferFrom function to handle the ERC721 transfer
        super.transferFrom(from, to, tokenId);

        // Emit an event to log the transfer of the GEM
        emit TransferGEM(from, to, tokenId);
    }

    /**
     * @notice Safely transfers a GEM token from one address to another.
     * @dev Overrides the ERC721 safeTransferFrom function. The transfer is only allowed when the contract is not paused.
     *      Checks if the recipient is a contract and if it can handle ERC721 tokens.
     * @param from The address to transfer the token from.
     * @param to The address to transfer the token to.
     * @param tokenId The ID of the token to transfer.
     * @param data Additional data with no specified format, sent in call to `to`.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override(ERC721Upgradeable, IERC721) whenNotPaused {
        // Check if the sender and recipient addresses are the same
        if(to == from) {
            revert SameSenderAndRecipient(); // Revert if they are the same
        }
        
        // Check if the GEM is locked
        if(Gems[tokenId].isLocked) {
            revert GemIsLocked(); // Revert if the GEM is locked
        }

        // Perform the GEM transfer logic
        _transferGEM(from, to, tokenId);

        // Call the parent contract's transferFrom function to handle the ERC721 transfer
        super.transferFrom(from, to, tokenId);

        // Check if the recipient is a contract and if it can handle ERC721 tokens
        _checkOnERC721(from, to, tokenId, data);

        // Emit an event to log the transfer of the GEM
        emit TransferGEM(from, to, tokenId);
    }

    /**
     * @notice Sets the lock status of a GEM token.
     * @dev Only callable by the marketplace or airdrop contracts.
     * @param _tokenId The ID of the token to set the lock status for.
     * @param _isLocked The lock status to set for the token.
     */
    function setIsLocked(uint256 _tokenId, bool _isLocked) external onlyMarketPlaceOrAirdrop {
        Gems[_tokenId].isLocked = _isLocked;
    }

    /**
     * @notice Adds a new color to the list of available colors.
     * @dev Only callable by the owner of the contract.
     * @param _colorName The name of the color to add.
     * @param _index1 The first index of the color.
     * @param _index2 The second index of the color.
     */
    function addColor(string memory _colorName, uint8 _index1, uint8 _index2) external onlyOwner {
        colorName[_index1][_index2] = _colorName;
        colors.push([_index1, _index2]);
        colorsCount++;

        emit ColorAdded(colorsCount, _colorName);

    }

    /**
     * @notice Sets the token URI for a specific GEM token.
     * @param tokenId The ID of the token to set the URI for.
     * @param _tokenURI The URI to set for the token.
     */
    function setTokenURI(uint256 tokenId, string memory _tokenURI) external {
        _setTokenURI(tokenId, _tokenURI);
    }

    //---------------------------------------------------------------------------------------
    //--------------------------PRIVATE/INERNAL FUNCTIONS------------------------------------
    //---------------------------------------------------------------------------------------

    /**
     * @notice Burns tokens internally.
     * @param _from Address from which tokens are burned.
     * @param _tokenIds Array of token IDs to burn.
     */
    function burnTokens(address _from, uint256[] memory _tokenIds) internal {
        for(uint256 i = 0; i < _tokenIds.length; ++i) {
            // delete GEM from the Gems array and every other ownership/approve storage
            delete Gems[_tokenIds[i]];
            ownershipTokenCount[_from]--;
            delete GEMIndexToOwner[_tokenIds[i]];
            // ERC721 burn function
            _burn(_tokenIds[i]);
        }
    }

    /**
     * @notice Checks if a color exists based on the given indices.
     * @param _index1 The first index of the color.
     * @param _index2 The second index of the color.
     * @return True if the color exists, false otherwise.
     */
    function colorExists(uint8 _index1, uint8 _index2) internal view returns (bool) {
        // Check if the color name is not an empty string
        return bytes(colorName[_index1][_index2]).length > 0;
    }

    /**
     * @notice Transfers a GEM from one address to another.
     * @dev Updates the GEM's cooldown period and adjusts ownership counts.
     * @param _from The address to transfer the GEM from.
     * @param _to The address to transfer the GEM to.
     * @param _tokenId The ID of the GEM to transfer.
     */
    function _transferGEM(address _from, address _to, uint256 _tokenId) private {
        // Update the GEM's cooldown period based on its rarity
        Gems[_tokenId].gemCooldownPeriod = block.timestamp + _getCooldownPeriod(Gems[_tokenId].rarity);
        // Increment the ownership count for the recipient
        ownershipTokenCount[_to]++;
        // Update the owner of the GEM
        GEMIndexToOwner[_tokenId] = _to;
        // Decrement the ownership count for the sender
        ownershipTokenCount[_from]--;
    }

    /**
     * @notice Fulfills a random number request and processes GEM mining.
     * @dev Implements the abstract function from DRBConsumerBase.
     * @dev Counts the total of eligible gems for mining
     * @dev Performs randomNumber % gemCount to get a number between 1 and gemCount
     * @dev Unlocks the initial Gem, reset the cooldown period and the randomRequestId
     * @dev Transfers the picked Gem from the treasury to the user
     * @param requestId The ID of the request.
     * @param randomNumber The random number generated.
     */
    function fulfillRandomWords(uint256 requestId, uint256 randomNumber) internal override {
        // Check if the request was made
        if(!s_requests[requestId].requested) {
            revert RequestNotMade();
        }
        // Mark the request as fulfilled and store the random number
        s_requests[requestId].fulfilled = true;
        s_requests[requestId].randomWord = randomNumber;
        uint256 _tokenId = s_requests[requestId].tokenId;

        // Retrieve the quadrants of the GEM
        uint8[4] memory quadrants = Gems[s_requests[requestId].tokenId].quadrants;
        
        // Count the number of GEMs by quadrant and emit an event
        (uint256 gemCount, uint256[] memory tokenIds) = countGemsByQuadrant(quadrants[0], quadrants[1], quadrants[2], quadrants[3]);
        emit CountGemsByQuadrant(gemCount, tokenIds);

        if(gemCount > 0) {
            // Select a GEM based on the random number
            uint256 modNbGemsAvailable = (randomNumber % gemCount);
            s_requests[requestId].chosenTokenId = tokenIds[modNbGemsAvailable];

            // reset storage variable of the initial GEM
            Gems[_tokenId].isLocked = false;
            Gems[_tokenId].randomRequestId = 0;
            Gems[_tokenId].gemCooldownPeriod = block.timestamp + _getCooldownPeriod(Gems[s_requests[requestId].tokenId].rarity);

            // Delete user mining data
            delete userMiningToken[ownerOf(_tokenId)][_tokenId];
            delete userMiningStartTime[ownerOf(_tokenId)][_tokenId];

            // we set mining try of the mined gem to 0 => mined gems can't mine other gems
            Gems[s_requests[requestId].chosenTokenId].miningTry = 0;

            // Transfer the GEM to the requester
            require(ITreasury(treasury).transferTreasuryGEMto(s_requests[requestId].requester, s_requests[requestId].chosenTokenId), "failed to transfer token");

            // Emit an event for the GEM mining claim
            emit GemMiningClaimed(_tokenId, msg.sender);
        } else {
            // No GEM available, set chosenTokenId to 0 and emit an event
            s_requests[requestId].chosenTokenId = 0;
            emit NoGemAvailable(_tokenId);
        }
    }

    /**
     * @notice Sets the token URI for a GEM.
     * @dev Overrides the internal function to ensure only the owner can set the URI.
     * @param tokenId The ID of the GEM.
     * @param _tokenURI The URI to set for the GEM.
     */
    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal override {
        // Ensure the sender is the owner of the GEM
        if(msg.sender != ownerOf(tokenId)) {
            revert NotGemOwner();
        }
        // Call the parent function to set the token URI
        super._setTokenURI(tokenId, _tokenURI);
    }


    /**
     * @notice Checks if the recipient address can handle ERC721 tokens.
     * @dev Calls the onERC721Received function on the recipient if it is a contract.
     * @param from The address sending the token.
     * @param to The address receiving the token.
     * @param tokenId The ID of the token being transferred.
     * @param data Additional data with no specified format.
     */
    function _checkOnERC721(address from, address to, uint256 tokenId, bytes memory data) private {
        // Check if the recipient is a contract
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, data) returns (bytes4 retval) {
                // Ensure the recipient contract returns the correct value
                if (retval != IERC721Receiver.onERC721Received.selector) {
                    revert ERC721InvalidReceiver(to);
                }
            } catch (bytes memory reason) {
                // Handle the case where the recipient contract does not implement the interface correctly
                if (reason.length == 0) {
                    revert ERC721InvalidReceiver(to);
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }
    }

    /**
     * @notice Gets the cooldown period for a GEM based on its rarity.
     * @param rarity The rarity of the GEM.
     * @return The cooldown period in seconds.
     */
    function _getCooldownPeriod(Rarity rarity) internal view returns (uint256) {
        // Return the cooldown period based on the rarity
        if (rarity == Rarity.COMMON) return 0;
        if (rarity == Rarity.RARE) return RareGemsCooldownPeriod;
        if (rarity == Rarity.UNIQUE) return UniqueGemsCooldownPeriod;
        if (rarity == Rarity.EPIC) return EpicGemsCooldownPeriod;
        if (rarity == Rarity.LEGENDARY) return LegendaryGemsCooldownPeriod;
        if (rarity == Rarity.MYTHIC) return MythicGemsCooldownPeriod;
        // Revert if the rarity is invalid
        revert("Invalid rarity");
    }

    //---------------------------------------------------------------------------------------
    //-----------------------------VIEW FUNCTIONS--------------------------------------------
    //---------------------------------------------------------------------------------------

    /**
     * @notice Retrieves the list of GEM IDs that are pre-mined and available in the treasury.
     * @return GemsAvailable An array of GEM IDs owned by the treasury.
     */
    function preMintedGemsAvailable() external view returns (uint256[] memory GemsAvailable) {
        // Return the list of GEM IDs owned by the treasury
        return tokensOfOwner(treasury);
    }

    /**
     * @notice Gets the number of GEM tokens owned by a specific address.
     * @param _owner The address to query the balance for.
     * @return count The number of GEM tokens owned by the specified address.
     */
    function balanceOf(address _owner) public view override(ERC721Upgradeable, IERC721) returns (uint256 count) {
         // Return the count of tokens owned by the address
        return ownershipTokenCount[_owner];
    }

    /**
     * @notice Retrieves the URI associated with a specific GEM token.
     * @param tokenId The ID of the GEM token to query.
     * @return The URI string associated with the specified token ID.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        // Ensure the token exists before querying its URI
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        // Return the token URI from the parent contract
        return super.tokenURI(tokenId);
    }

    /**
     * @notice Checks if a GEM token exists.
     * @param tokenId The ID of the GEM token to check.
     * @return True if the token exists, false otherwise.
     */
    function _exists(uint256 tokenId) internal view returns (bool) {
        // Check if the token ID is associated with an owner
        return GEMIndexToOwner[tokenId] != address(0);
    }

    /**
     * @notice Retrieves the details of a specific GEM by its token ID.
     * @param tokenId The ID of the GEM to retrieve.
     * @return The Gem struct containing details of the specified GEM.
     */
    function getGem(uint256 tokenId) public view returns (Gem memory) {
        // Iterate through the list of Gems to find the one with the specified token ID
        for (uint256 i = 0; i < Gems.length; ++i) {
            if (Gems[i].tokenId == tokenId) {
                return Gems[i];
            }
        }
        // Revert if the GEM with the specified token ID does not exist
        revert("Gem with the specified tokenId does not exist");
    }

    /**
     * @notice Retrieves the value of a GEM based on its rarity.
     * @param _rarity The rarity of the GEM.
     * @return value The value associated with the specified rarity.
     */
    function getValueBasedOnRarity(Rarity _rarity) public view returns(uint256 value) {
        // Determine the value based on the rarity of the GEM
        if(_rarity == Rarity.COMMON) {
            value = CommonGemsValue;
        } else if(_rarity == Rarity.RARE) {
            value = RareGemsValue;
        } else if(_rarity == Rarity.UNIQUE) {
            value = UniqueGemsValue;
        } else if(_rarity == Rarity.EPIC) {
            value = EpicGemsValue;
        } else if(_rarity == Rarity.LEGENDARY) {
            value = LegendaryGemsValue;
        } else if(_rarity == Rarity.MYTHIC) {
            value = MythicGemsValue;
        } else {
            // Revert if the rarity is not recognized
            revert("wrong rarity");
        }
    }

    /**
     * @notice Checks if a specific GEM token is locked.
     * @param _tokenId The ID of the GEM token to check.
     * @return True if the token is locked, false otherwise.
     */
    function isTokenLocked(uint256 _tokenId) public view returns(bool) {
        // Return the lock status of the GEM
        return Gems[_tokenId].isLocked;
    }

    /**
     * @notice Retrieves the status of a random request by its ID.
     * @param _requestId The ID of the request to retrieve.
     * @return The RequestStatus struct containing details of the request.
     */
    function getRandomRequest(uint256 _requestId) external view returns(RequestStatus memory) {
        // Return the request status for the specified request ID
        return s_requests[_requestId];
    }

    /**
     * @notice Retrieves the name of a color based on its indices.
     * @param _index1 The first index of the color.
     * @param _index2 The second index of the color.
     * @return The name of the color as a string.
     */
    function getColorName(uint8 _index1, uint8 _index2) public view returns (string memory) {
        // Return the color name associated with the specified indices
        return colorName[_index1][_index2];
    }

    /**
     * @notice Counts the number of Gems from the treasury with quadrants less than the specified values.
     * @param quadrant1 The first quadrant value to compare.
     * @param quadrant2 The second quadrant value to compare.
     * @param quadrant3 The third quadrant value to compare.
     * @param quadrant4 The fourth quadrant value to compare.
     * @return The count of Gems and an array of their token IDs.
     */
    function countGemsByQuadrant(uint8 quadrant1, uint8 quadrant2, uint8 quadrant3, uint8 quadrant4) internal view returns (uint256, uint256[] memory) {
        uint256 count = 0;
        uint256[] memory tokenIds = new uint256[](Gems.length);
        uint256 index = 0;
        uint8 sumOfQuadrants = quadrant1 + quadrant2 + quadrant3+ quadrant4;

        // Iterate through the Gems to count those with quadrants less than the specified sum
        for (uint256 i = 0; i < Gems.length; ++i) {
            uint8 GemSumOfQuadrants = Gems[i].quadrants[0] + Gems[i].quadrants[1] + Gems[i].quadrants[2] + Gems[i].quadrants[3];
            if (GemSumOfQuadrants < sumOfQuadrants && 
                GEMIndexToOwner[i] == treasury &&
                !Gems[i].isLocked
            ) {
                tokenIds[index] = Gems[i].tokenId;
                unchecked{
                    index++;
                    count++;
                } 
            }
        }
        // Resize the array to the actual count
        uint256[] memory result = new uint256[](count);
        for (uint256 j = 0; j < count; ++j) {
            result[j] = tokenIds[j];
        }

        return (count, result);
    }

    /**
     * @notice Retrieves a list of GEM IDs available for random pack selection.
     * @return The count of available Gems and an array of their token IDs.
     */
    function getGemListAvailableForRandomPack() external view returns (uint256, uint256[] memory) {
        uint256 count = 0;
        uint256[] memory tokenIds = new uint256[](Gems.length);
        uint256 index = 0;
        
        // Iterate through the Gems to find those available for random pack selection
        for (uint256 i = 0; i < Gems.length; ++i) {
            if (GEMIndexToOwner[i] == treasury &&
                !Gems[i].isLocked
            ) {
                tokenIds[index] = Gems[i].tokenId;
                unchecked{
                    index++;
                    count++;
                } 
            }
        }

        // Resize the array to the actual count
        uint256[] memory result = new uint256[](count);
        for (uint256 j = 0; j < count; ++j) {
            result[j] = tokenIds[j];
        }

        return (count, result);
    }

    /**
     * @notice Returns a list of all GEM IDs assigned to a specific owner.
     * @param _owner The address of the GEM owner.
     * @return ownerTokens An array of GEM IDs owned by the specified address.
     */
    function tokensOfOwner(address _owner) public view returns (uint256[] memory ownerTokens) {
        uint256 tokenCount = balanceOf(_owner);

        if (tokenCount == 0) {
            // Return an empty array if the owner has no tokens
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 totalGems = totalSupply();
            uint256 resultIndex = 0;

            // Iterate through all GEM IDs to find those owned by the specified address
            uint256 gemId;

            for (gemId = 1; gemId <= totalGems; ++gemId) {
                if (GEMIndexToOwner[gemId] == _owner) {
                    result[resultIndex] = gemId;
                    resultIndex++;
                }
            }

            return result;
        }
    }

    /**
     * @notice Retrieves the total supply of GEM tokens.
     * @return The total number of GEM tokens in existence.
     */
    function totalSupply() public view returns (uint256) {
        // Return the total number of Gems, excluding the zero index
        return Gems.length - 1;
    }

    /**
     * @notice Calculates the total value of all GEMs in supply.
     * @return totalValue The cumulative value of all GEMs.
     */
    function getGemsSupplyTotalValue() external view returns(uint256 totalValue) {
        // Sum the values of all Gems to get the total supply value
        for (uint256 i = 0; i < Gems.length; ++i) {
            totalValue += Gems[i].value;
        }
    }

    //---------------------------------------------------------------------------------------
    //-------------------------------STORAGE GETTERS-----------------------------------------
    //---------------------------------------------------------------------------------------

    function getTreasuryAddress() external view returns(address) {return treasury;}
    function getTonAddress() external view returns(address) {return ton;}
    function getWstonAddress() external view returns(address) {return wston;}
    function getMarketPlaceAddress() external view returns(address) {return marketplace;}
    function getAirdropAddress() external view returns(address) {return airdrop;}
    function getCommonGemsValue() external view returns(uint256) { return CommonGemsValue;}
    function getRareGemsValue() external view returns(uint256) {return RareGemsValue;}
    function getUniqueGemsValue() external view returns(uint256) {return UniqueGemsValue;}
    function getEpicGemsValue() external view returns(uint256) {return EpicGemsValue;}
    function getLegendaryGemsValue() external view returns(uint256) {return LegendaryGemsValue;}
    function getMythicGemsValue() external view returns(uint256) {return MythicGemsValue;}
    function getRareminingTry() external view returns(uint8) { return RareminingTry;}
    function getUniqueminingTry() external view returns(uint8) { return UniqueminingTry;}
    function getEpicminingTry() external view returns(uint8) { return EpicminingTry;}
    function getLegendaryminingTry() external view returns(uint8) { return LegendaryminingTry;}
    function getMythicminingTry() external view returns(uint8) { return MythicminingTry;}
    function getRareGemsMiningPeriod() external view returns(uint32) { return RareGemsMiningPeriod;}
    function getUniqueGemsMiningPeriod() external view returns(uint32) { return UniqueGemsMiningPeriod;}
    function getEpicGemsMiningPeriod() external view returns(uint32) { return EpicGemsMiningPeriod;}
    function getLegendaryGemsMiningPeriod() external view returns(uint32) { return LegendaryGemsMiningPeriod;}
    function getMythicGemsMiningPeriod() external view returns(uint32) { return MythicGemsMiningPeriod;}
    function getRareGemsCooldownPeriod() external view returns(uint32) { return RareGemsCooldownPeriod;}
    function getUniqueGemsCooldownPeriod() external view returns(uint32) { return UniqueGemsCooldownPeriod;}
    function getEpicGemsCooldownPeriod() external view returns(uint32) { return EpicGemsCooldownPeriod;}
    function getLegendaryGemsCooldownPeriod() external view returns(uint32) { return LegendaryGemsCooldownPeriod;}
    function getMythicGemsCooldownPeriod() external view returns(uint32) { return MythicGemsCooldownPeriod;}
    function getRequestIds() external view returns(uint256[] memory) { return requestIds;}
    function getRequestCount() external view returns(uint256) { return requestCount;}
    function getOwnershipTokenCount(address _user) external view returns(uint256) { return ownershipTokenCount[_user];}
}

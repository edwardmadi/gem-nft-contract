// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AuthControl} from "../common/AuthControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../proxy/ProxyStorage.sol";

import { WstonSwapPoolStorageV2 } from "./WstonSwapPoolStorageV2.sol";

/**
 * @title WstonSwapPoolV2 Contract for Token Swapping
 * @author TOKAMAK OPAL TEAM
 * @notice This contract facilitates the swapping of WSTON tokens for TON tokens directly from users to the treasury
 * It manages the exchange rate through a staking index.
 * The contract includes mechanisms for pausing operations and ensuring secure token transfers.
 * @dev The contract uses OpenZeppelin's ReentrancyGuard for security and AuthControl for access management.
 */
contract WstonSwapPoolV2 is ProxyStorage, AuthControl, ReentrancyGuard, WstonSwapPoolStorageV2 {

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
     * @notice Pauses the contract, preventing certain actions.
     * @dev Only callable by the owner when the contract is not paused.
     */
    function pause() public onlyOwner whenNotPaused {
        paused = true;
    }

    /**
     * @notice Unpauses the contract, allowing actions to be performed.
     * @dev Only callable by the owner when the contract is paused.
     */
    function unpause() public onlyOwner whenNotPaused {
        paused = false;
    }

    /**
     * @notice Initializes the WstonSwapPool contract with the given parameters.
     * @param _ton The address of the TON token contract.
     * @param _wston The address of the WSTON token contract.
     * @param _initialStakingIndex The initial staking index value.
     * @param _treasury The address of the treasury contract.
     * @dev Can only be called once. Grants the caller the default admin role.
     */
    function initialize(
        address _ton, 
        address _wston,
        uint256 _initialStakingIndex, 
        address _treasury
    ) external {
        require(!initialized, "already initialized");   
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        ton = _ton;
        wston = _wston;
        treasury = _treasury;
        stakingIndex = _initialStakingIndex;
        initialized = true;
    }

    //---------------------------------------------------------------------------------------
    //--------------------------------EXTERNAL FUNCTIONS-------------------------------------
    //---------------------------------------------------------------------------------------

    /**
     * @notice Swaps a specified amount of WSTON for TON tokens.
     * @dev The function checks allowances and balances before performing the swap.
     * Emits a `SwappedWstonForTon` event upon successful swap.
     * @dev Before using this funciton, treasury must approve this contract for TON => type(uint256).max 
     * @param wstonAmount The amount of WSTON tokens to swap.
     */
    function swap(uint256 wstonAmount) external nonReentrant {
        if(IERC20(wston).allowance(msg.sender, address(this)) < wstonAmount) {
            revert WstonAllowanceTooLow();
        }
        if(IERC20(wston).balanceOf(msg.sender) < wstonAmount) {
            revert WstonBalanceTooLow();
        }
        
        // calculate the 
        uint256 tonAmount = ((wstonAmount * stakingIndex) / DECIMALS) / (10**9);
        
        // Checks if treasury holds enough TON
        if(IERC20(ton).balanceOf(treasury) < tonAmount || IERC20(ton).allowance(treasury, address(this)) < tonAmount) {
            revert ContractTonBalanceOrAllowanceTooLow();
        }

        // transfers WSTON from the caller to the treasury
        _safeTransferFrom(IERC20(wston), msg.sender, treasury, wstonAmount);
        // Transfers TON from the treasury to the user
        _safeTransferFrom(IERC20(ton), treasury, msg.sender, tonAmount);

        emit SwappedWstonForTon(msg.sender, tonAmount, wstonAmount);
    }

    /**
     * @notice Updates the staking index used for calculating swap rates.
     * @dev The new index must be greater than or equal to 10^27.
     * Emits a `StakingIndexUpdated` event upon successful update.
     * @param newIndex The new staking index value.
     */
    function updateStakingIndex(uint256 newIndex) external onlyOwner {
        if(newIndex < 10**27) {
            revert WrongStakingIndex();
        }
        stakingIndex = newIndex;
        emit StakingIndexUpdated(newIndex);
    }

    //---------------------------------------------------------------------------------------
    //-----------------------------INTERNAL/PRIVATE FUNCTIONS--------------------------------
    //---------------------------------------------------------------------------------------

    function _safeTransferFrom(IERC20 token, address sender, address recipient, uint256 amount) private {
        bool sent = token.transferFrom(sender, recipient, amount);
        require(sent, "Token transfer failed");
    }

    //---------------------------------------------------------------------------------------
    //------------------------STORAGE GETTER / VIEW FUNCTIONS--------------------------------
    //---------------------------------------------------------------------------------------

    function getStakingIndex() external view returns(uint256) {return stakingIndex;}

}
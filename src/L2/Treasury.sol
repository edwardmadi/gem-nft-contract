// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { GemFactory } from "./GemFactory.sol";
import { GemFactoryStorage } from "./GemFactoryStorage.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract Treasury is GemFactory, IERC721Receiver {
    using SafeERC20 for IERC20;

    address internal _gemFactory;

    modifier onlyGemFactory() {
        require(msg.sender == _gemFactory, "not GemFactory");
        _;
    }

    constructor(address coordinator, address _wston, address _ton) GemFactory(coordinator) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        wston = _wston;
        ton = _ton;
    }

    function setGemFactory(address gemFactory) external onlyOwner {
        require(gemFactory != address(0), "Invalid address");
        _gemFactory = gemFactory;
    }

    function approveGemFactory(uint256 _amount) external onlyOwner {
        require(wston != address(0), "wston address not set");
        IERC20(wston).approve(_gemFactory, _amount);
    }

    
    function transferWSTON(address _to, uint256 _amount) external whenNotPaused onlyGemFactory returns(bool) {
        require(_to != address(0), "address zero");
        uint256 contractWSTONBalance = getWSTONBalance();
        require(contractWSTONBalance >= _amount, "Unsuffiscient WSTON balance");

        IERC20(wston).safeTransfer(_to, _amount);
        return true;
    }

    function createPreminedGEM(
        GemFactoryStorage.Rarity _rarity, 
        string memory _color, 
        uint128 _value, 
        bytes2 _quadrants, 
        string memory _colorStyle,
        string memory _backgroundColor,
        string memory _backgroundColorStyle,
        uint256 _cooldownPeriod,
        string memory _tokenURI
    ) external onlyOwner returns (uint256) {
        return GemFactory(_gemFactory).createGEM(
            _rarity,
            _color,
            _value,
            _quadrants,
            _colorStyle,
            _backgroundColor,
            _backgroundColorStyle,
            _cooldownPeriod,
            _tokenURI
        );
    }

    function createPreminedGEMPool(
        GemFactoryStorage.Rarity[] memory _rarities,
        string[] memory _colors,
        uint128[] memory _values,
        bytes2[] memory _quadrants,
        string[] memory _colorStyle,
        string[]memory _backgroundColor,
        string[] memory _backgroundColorStyle,
        uint256[] memory _cooldownPeriod,
        string[] memory _tokenURIs
    ) external onlyOwner returns (uint256[] memory) {
        return GemFactory(_gemFactory).createGEMPool(
            _rarities,
            _colors,
            _values,
            _quadrants,
            _colorStyle,
            _backgroundColor,
            _backgroundColorStyle,
            _cooldownPeriod,
            _tokenURIs
        );
    }

    function approveGEMTransfer(address _to, uint256 _tokenId) external onlyOwner {
        GemFactory(_gemFactory).approveGEM(_to, _tokenId);
    }

    function transferTreasuryGEMto(address _to, uint256 _tokenId) external onlyOwner {
        GemFactory(_gemFactory).transferGEM(_to, _tokenId);
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

    //---------------------------------------------------------------------------------------
    //-----------------------------VIEW FUNCTIONS--------------------------------------------
    //---------------------------------------------------------------------------------------

    // Function to check the balance of TON token within the contract
    function getTONBalance() public view returns (uint256) {
        return IERC20(ton).balanceOf(address(this));
    }

    // Function to check the balance of WSTON token within the contract
    function getWSTONBalance() public view returns (uint256) {
        return IERC20(wston).balanceOf(address(this));
    }

    function getGemFactoryAddress() public view returns (address) {
        return _gemFactory;
    }
    
}
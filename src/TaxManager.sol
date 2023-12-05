// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract TaxManager {
  uint64 private immutable ETH_CHAIN_SELECTOR = 5009297550715157269;
  uint64 private immutable ETH_SEPOLIA_CHAIN_SELECTOR = 16015286601757825753;

  uint256 public gasLimitPerUser;
  uint64 public currentChainSelector;
  mapping(uint64 => uint256) gasPricePerChainSelector;
  AggregatorV3Interface ethereumMainnetPriceFeed;

  constructor(uint256 _gasLimitPerUser, uint64 _currentChainSelector) {
    gasLimitPerUser = _gasLimitPerUser;
    currentChainSelector = _currentChainSelector;
    ethereumMainnetPriceFeed = AggregatorV3Interface(0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C);
  }

  function getGasLimitPerUser() public view returns (uint256) {
      return gasLimitPerUser;
  }

  function setGasLimitPerUser(uint256 _newGasLimit) public {
      gasLimitPerUser = _newGasLimit;
  }

  function getGasPricePerChainSelector(uint64 _chainSelector) public view returns (uint256) {
        return gasPricePerChainSelector[_chainSelector];
    }

  function setGasPricePerChainSelector(uint64 _chainSelector, uint256 _newGasPrice) public {
      gasPricePerChainSelector[_chainSelector] = _newGasPrice;
  }

  function getDepositTax() public view returns (uint256) {
    if (currentChainSelector == ETH_CHAIN_SELECTOR) {
      (,int256 answer,,,) = ethereumMainnetPriceFeed.latestRoundData();
      return gasLimitPerUser * uint256(answer);
    }

    return gasLimitPerUser * gasPricePerChainSelector[currentChainSelector];
  }

}
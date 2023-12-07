// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TaxManager is Ownable {
  uint64 private immutable ETH_CHAIN_SELECTOR = 5009297550715157269;
  uint64 private immutable ETH_SEPOLIA_CHAIN_SELECTOR = 16015286601757825753;

  uint256 public protocolFee;
  uint256 public gasLimitPerUser;
  uint64 public currentChainSelector;
  mapping(uint64 => uint256) gasPricePerChainSelector;
  AggregatorV3Interface ethereumMainnetPriceFeed;
  uint256 lastDestinationChainFees;

  constructor(uint64 _currentChainSelector, address _owner) Ownable(_owner) {
    currentChainSelector = _currentChainSelector;
    protocolFee = 10; // 10% over tips
    gasLimitPerUser = 45000; // Average of bridge cost > 15 users
    gasPricePerChainSelector[ETH_SEPOLIA_CHAIN_SELECTOR] = 80000000; // 0.08 Gwei
    ethereumMainnetPriceFeed = AggregatorV3Interface(0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C);
    lastDestinationChainFees = 500_000_000_000_000; // Gas needed for ccpiSend 
  }

  function _payRewards(uint256 _feesInDestinationChain, address _protocol, address _caller) internal {
    _setLastDestinationChainFees(_feesInDestinationChain);
    
    uint256 contractBalance = address(this).balance;

    if (contractBalance < _feesInDestinationChain){
      return;
    }

    uint256 claimableReward = contractBalance - _feesInDestinationChain;

    // Pay the protocol
    uint256 protocolAmount = (getProtocolFee() * claimableReward) / 100;
    (bool protocolSuccess,) = payable(_protocol).call{value: protocolAmount }("");
    require(protocolSuccess, "Transfer ETH to protocol failed");

    // Pay back for the call
    (bool callerSuccess,) = payable(_caller).call{value: claimableReward - protocolFee }("");
    require(callerSuccess, "Transfer ETH to msg.sender failed");
  }

  function setProtocolFee(uint256 _newGasLimit) external onlyOwner {
      protocolFee = _newGasLimit;
  }

  function setGasLimitPerUser(uint256 _newGasLimit) external onlyOwner {
      gasLimitPerUser = _newGasLimit;
  }

  function setGasPricePerChainSelector(uint64 _chainSelector, uint256 _newGasPrice) external onlyOwner {
      gasPricePerChainSelector[_chainSelector] = _newGasPrice;
  }

  function _setLastDestinationChainFees(uint256 _fees) internal returns (uint256) {
    lastDestinationChainFees =_fees;
    return _fees;
  }

  function getProtocolFee() public view returns (uint256) {
      return protocolFee;
  }

  function getGasLimitPerUser() public view returns (uint256) {
      return gasLimitPerUser;
  }

  function getCurrentChainSelector() public view returns (uint64) {
    return currentChainSelector;
  }

  function getGasPricePerChainSelector(uint64 _chainSelector) public view returns (uint256) {
        return gasPricePerChainSelector[_chainSelector];
    }

  function getDepositTax() public view returns (uint256) {
    uint256 finalGasLimit = (gasLimitPerUser * (100 + protocolFee)) / 100;
    
    if (currentChainSelector == ETH_CHAIN_SELECTOR) {
      (,int256 answer,,,) = ethereumMainnetPriceFeed.latestRoundData();
      return (finalGasLimit * uint256(answer));
    }

    return finalGasLimit * gasPricePerChainSelector[currentChainSelector];
  }

  function getLastDestinationChainFees() public view returns (uint256) {
        return lastDestinationChainFees;
    }

}
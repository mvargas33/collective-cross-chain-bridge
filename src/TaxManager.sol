// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TaxManager is Ownable {
    uint64 private immutable ETH_CHAIN_SELECTOR = 5009297550715157269;
    uint64 private immutable ETH_SEPOLIA_CHAIN_SELECTOR = 16015286601757825753;

    uint256 public protocolFee;
    uint256 public gasLimitPerUser;
    uint256 public depositTax;
    uint64 public currentChainSelector;
    mapping(uint64 => uint256) gasPricePerChainSelector;
    AggregatorV3Interface ethereumMainnetPriceFeed;
    uint256 destinationChainFees;
    uint256 accumProtocolFees;
    mapping(address => uint256) callerRewards;

    constructor(uint64 _currentChainSelector, address _owner) Ownable(_owner) {
        currentChainSelector = _currentChainSelector;
        protocolFee = 10; // 10% over tips
        gasLimitPerUser = 45_000; // Average of bridge cost > 15 users
        gasPricePerChainSelector[ETH_SEPOLIA_CHAIN_SELECTOR] = 80_000_000_000; // 80 Gwei
        ethereumMainnetPriceFeed = AggregatorV3Interface(0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C);
        destinationChainFees = 500_000_000_000_000; // Gas needed for ccpiSend
        accumProtocolFees = 0;
        depositTax =
            (gasLimitPerUser * (100 + protocolFee)) * gasPricePerChainSelector[ETH_SEPOLIA_CHAIN_SELECTOR] / 100;
    }

    function claimProtocolRewards() external onlyOwner {
        (bool sucecss,) = payable(owner()).call{value: accumProtocolFees}("");
        require(sucecss, "Transfer ETH to protocol failed");

        accumProtocolFees = 0;
    }

    function claimRewards() public {
        require(callerRewards[msg.sender] > 0, "You dont have rewards");

        (bool success,) = payable(msg.sender).call{value: callerRewards[msg.sender]}("");
        require(success, "Transfer reward to user failed");

        callerRewards[msg.sender] = 0;
    }

    function _payRewards() internal {
        uint256 remainingBalance = address(this).balance - accumProtocolFees;

        if (remainingBalance < destinationChainFees) {
            return; // Save for next call
        }

        // Reward the protocol
        uint256 protocolAmount = (protocolFee * (remainingBalance - destinationChainFees)) / 100;
        accumProtocolFees += protocolAmount;

        // Reward the caller
        uint256 remainingReward = address(this).balance - destinationChainFees - accumProtocolFees;
        callerRewards[msg.sender] += remainingReward;
    }

    function setProtocolFee(uint256 _newProtocolFee) external onlyOwner {
        protocolFee = _newProtocolFee;
        depositTax = (gasLimitPerUser * (100 + _newProtocolFee)) * gasPricePerChainSelector[currentChainSelector] / 100;
    }

    function setGasLimitPerUser(uint256 _newGasLimit) external onlyOwner {
        gasLimitPerUser = _newGasLimit;
        depositTax = (_newGasLimit * (100 + protocolFee)) * gasPricePerChainSelector[currentChainSelector] / 100;
    }

    function setGasPricePerChainSelector(uint64 _chainSelector, uint256 _newGasPrice) external onlyOwner {
        gasPricePerChainSelector[_chainSelector] = _newGasPrice;
    }

    /**
     * Function that changes the estimated gas limit on destination chain. Dont use in bridge() to save gas
     */
    function setDestinationChainFees(uint256 _fees) external onlyOwner returns (uint256) {
        destinationChainFees = _fees;
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

    /**
     * Return the fee per deposit, equal to estimated gas limit per per, per bridge, around 35k
     * multiplied by the gas in the source chain. Uses Chainlink Price Feed for ethereum mainnet,
     * that gets the fast-gas value in wei from an oracle. If not, uses an average gas price per chain
     * stores in the contract, set by the owner.
     *
     * Adds 10% more to the computed value, as a protocol fee that is then deducted in the bridge() call
     */
    function getDepositTax() public view returns (uint256) {
        return depositTax;
    }

    /**
     * Only makes sense to eth mainnet: ETH_CHAIN_SELECTOR
     */
    function getDynamicDepostiTax() public view returns (uint256) {
        uint256 finalGasLimit = (gasLimitPerUser * (100 + protocolFee)) / 100; // Add 10% as protocol fee

        (, int256 answer,,,) = ethereumMainnetPriceFeed.latestRoundData();
        return (finalGasLimit * uint256(answer));
    }

    function getDestinationChainFees() public view returns (uint256) {
        return destinationChainFees;
    }

    /**
     * If the contract has less than the amount needed to call the function in destination chain,
     * neither the protocol nor the caller receive a reward. If there is some balance left, the reward
     * gets split by {protocolFee} % the protocol and the rest to the caller
     */
    function getEstimatedRewards() external view returns (uint256, uint256) {
        uint256 balance = address(this).balance;

        if (balance < 2 * destinationChainFees) {
            return (0, 0);
        }

        uint256 reward = balance - destinationChainFees;
        uint256 protocolAmount = (getProtocolFee() * reward) / 100;
        uint256 callerReward = reward - protocolAmount;

        return (protocolAmount, callerReward);
    }
}

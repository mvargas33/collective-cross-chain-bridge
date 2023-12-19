// SPDX-License-Identifier: Apache License 2.0
pragma solidity 0.8.20;

import {IOptimisticCCCB} from "./IOptimisticCCCB.sol";

interface ISourceChainOptimisticCCCB is IOptimisticCCCB {
    event UserDeposit(address _sender, uint256 _amount, uint256 roundId);
    event DepositTaxPaid(address _sender, uint256 _amount);
    event RoundBridged(uint256 roundId, address[] _participants, uint256[] _balances, uint256 _tokenAmount, uint256 _destinationFees, bytes32 _ccipMessageId);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {SourceChainCCCB} from "../../src/SourceChainCCCB.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract ExposedSourceChainCCCB is SourceChainCCCB {
    constructor(
        address _router,
        address _tokenAddress,
        uint64 _destinationChainSelector,
        address _destinationContract,
        uint256 _nativeTokenTax
    ) SourceChainCCCB(_router, _tokenAddress, _destinationChainSelector, _destinationContract, _nativeTokenTax) {}

    function exposed_bridgeBalances(uint256 currentTokenAmount) public returns (bytes32, uint256) {
        return _bridgeBalances(currentTokenAmount);
    }

    function exposed_ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) public {
        _ccipReceive(any2EvmMessage);
    }

    function exposed_nextRound() public {
        _nextRound();
    }
}

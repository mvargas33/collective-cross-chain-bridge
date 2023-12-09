// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {SourceChainCCCB} from "../../src/SourceChainCCCB.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract ExposedSourceChainCCCB is SourceChainCCCB {
    constructor(address _router, uint64 _destinationChainSelector, uint64 _currentChainSelector, address _owner, address _tokenAddress)
        SourceChainCCCB(_router, _destinationChainSelector, _currentChainSelector, _owner, _tokenAddress)
    {}

    function exposed_bridgeBalances() public returns (bytes32, uint256) {
        return _bridgeBalances();
    }

    function exposed_ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) public {
        _ccipReceive(any2EvmMessage);
    }

    function exposed_nextRound() public {
        _nextRound();
    }
}

// SPDX-License-Identifier: Apache License 2.0
pragma solidity 0.8.20;

import {DestinationChainCCCB} from "../../src/DestinationChainCCCB.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract ExposedDestinationChainCCCB is DestinationChainCCCB {
    constructor(address _router, uint64 _destinationChainSelector, address _owner, address _tokenAddress)
        DestinationChainCCCB(_router, _destinationChainSelector, _owner, _tokenAddress)
    {}

    function exposed_ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) public {
        _ccipReceive(any2EvmMessage);
    }

    function exposed_sendMessage() public {
        _sendMessage();
    }
}

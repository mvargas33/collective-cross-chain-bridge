// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IDestinationChainCCCB {
    enum ContractState {
        OPEN,
        BLOCKED
    }

    struct Round {
        uint256 roundId;
        uint256[] balances;
        address[] participants;
    }
}

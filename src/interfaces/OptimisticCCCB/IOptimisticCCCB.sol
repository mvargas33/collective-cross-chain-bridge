// SPDX-License-Identifier: Apache License 2.0
pragma solidity 0.8.20;

interface IOptimisticCCCB {
    struct Round {
        address[] participants;
        mapping(address => uint256) balances;
    }

    struct FullRound {
        uint256 roundId;
        address[] participants;
        mapping(address => uint256) balances;
    }

    struct SimpleRound {
        uint256 roundId;
        address[] participants;
        uint256[] balances;
    }
}

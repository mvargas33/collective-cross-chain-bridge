// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {Withdraw} from "./utils/Withdraw.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract CollectiveCrossChainBridgeEthereum is Withdraw {
    using SafeERC20 for IERC20;

    enum ContractState {
        OPEN,
        BLOCKED
    }

    address immutable i_router = 0xD0daae2231E9CB96b94C8512223533293C3693Bf; // ETH Sepolia
    address immutable i_link = 0x779877A7B0D9E8603169DdbD7836e478b4624789; // LINK Sepolia
    uint64 immutable polygonChainSelector = 12532609583862916517; // Polygon Mumbai
    IERC20 immutable tokenAddress = IERC20(0x1a93Dd2Ff0308F0Ae65a94aDC191E8A43d2e978c); // Only token allowed to bridge
    address immutable receiverInPolygon = 0x1a93Dd2Ff0308F0Ae65a94aDC191E8A43d2e978c; // polygon contract address. TODO: Add setter/getter onlyOwner, the burn keys

    ContractState private contractState = ContractState.OPEN;

    struct Round {
        uint256 roundId;
        mapping(address => uint256) balances;
        address[] participants;
    }

    mapping(uint256 => Round) rounds;
    uint256 currentRound;

    mapping(uint256 => bool) successfulRounds;

    constructor() {
        LinkTokenInterface(i_link).approve(i_router, type(uint256).max);
        currentRound = 0;
        rounds[0].roundId = 0;
    }

    receive() external payable {}

    function deposit(uint256 amount) {
        require(contractState == ContractState.OPEN, "Wait for the next round");
        require(msg.sender != address(0));

        tokenAddress.safeTransferFrom(msg.sender, address(this), amount);

        if (rounds[currentRound].balances[msg.sender] == 0) {
            rounds[currentRound].participants.push(msg.sender);
        }

        rounds[currentRound].balances[msg.sender] += amount;
    }

    function bridge() external returns (bytes32 messageId) {
        require(contractState == ContractState.OPEN, "Wait for the next round");
        require(msg.sender != address(0));

        contractState = ContractState.BLOCKED;

        // TODO: Call bridge to receiverInPolygon

        messageid = sendRoundToPolygon();

        return messageId;
    }

    function sendRoundToPolygon() external returns (bytes32 messageId) {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverInPolygon),
            data: abi.encode(rounds[currentRound]),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: address(0)
        });

        uint256 fee = IRouterClient(i_router).getFee(polygonChainSelector, message);
        messageId = IRouterClient(i_router).ccipSend{value: fee}(polygonChainSelector, message);

        return messageId;
    }

    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        uint64 chainSelector = any2EvmMessage.chainSelector; // fetch the source chain identifier (aka selector)
        address sender = abi.decode(any2EvmMessage.sender, (address)); // abi-decoding of the sender address

        require(chainSelector == polygonChainSelector, "Message from invalid chain");
        require(sender == receiverInPolygon, "Invalid sender");

        uint256 memory roundIdProcessed = abi.decode(any2EvmMessage.data, (uint256)); // abi-decoding of the sent string message

        successfulRounds[roundIdProcessed] = true;
        currentRound += 1;
        contractState = ContractState.OPEN;
    }
}

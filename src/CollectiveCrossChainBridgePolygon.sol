// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.20;

// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
// import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
// import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
// import {Withdraw} from "./utils/Withdraw.sol";

// /**
//  * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
//  * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
//  * DO NOT USE THIS CODE IN PRODUCTION.
//  */
// contract CollectiveCrossChainBridgePolygon is Withdraw {
//     using SafeERC20 for IERC20;

//     enum ContractState {
//         OPEN,
//         BLOCKED
//     }

//     address immutable i_router = 0xD0daae2231E9CB96b94C8512223533293C3693Bf; // Polygon mainnet
//     address immutable i_link = 0x779877A7B0D9E8603169DdbD7836e478b4624789; // LINK Polygon
//     uint64 immutable ethereumChainSelector = 12532609583862916517; // Ethereum mainnet
//     IERC20 immutable fxTokenAddress = IERC20(0x1a93Dd2Ff0308F0Ae65a94aDC191E8A43d2e978c); // Only token allowed to receive
//     address immutable receiverInEthereum = 0x1a93Dd2Ff0308F0Ae65a94aDC191E8A43d2e978c; // ethereum contract address. TODO: Add setter/getter onlyOwner, the burn keys

//     ContractState private contractState = ContractState.OPEN;

//     struct Round {
//         uint256 roundId;
//         mapping(address => uint256) balances;
//         address[] participants;
//     }

//     mapping(uint256 => Round) rounds;
//     uint256 currentRound;
//     uint256 currentRoundTotalBalance;

//     mapping(uint256 => bool) successfulRounds;
//     mapping(address => uint256) pendingBalances;

//     constructor() {
//         LinkTokenInterface(i_link).approve(i_router, type(uint256).max);
//         currentRound = 0;
//         rounds[0].roundId = 0;
//     }

//     receive() external payable {}

//     /**
//      * If the fx token arrived at the contract, send all pendingBalances to participants of this round. Then unlock ethereum contract
//      * by sending an ACK with the round id.
//      */
//     function sendBalances() public {
//         require(msg.sender != address(0));
//         require(fxTokenAddress.balanceOf(address(this)) >= currentRoundTotalBalance, "Fx token has not arrived yet");

//         for (uint256 i = 0; i < rounds[currentRound].participants.length; i++) {
//             fxTokenAddress.safeTrasfer(rounds[currentRound].participants[i], rounds[currentRound].balances[rounds[currentRound].participants[i]]);
//             pendingBalances[rounds[currentRound].participants[i]] -= rounds[currentRound].balances[rounds[currentRound].participants[i]];
//         }

//         successfulRounds[currentRound] = true;

//         _sendAckToEthereum(currentRound); // Important to unlock ethereum contract only when all balances have been distributed
//     }

//     /**
//      * Once all balances have been distributed, sends an ACK to unlock the contract in ethereum, and repeat the prcoess
//      */
//     function _sendAckToEthereum(uint256 roundIdReceived) internal {
//         Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
//             receiver: abi.encode(receiverInEthereum),
//             data: abi.encode(roundIdReceived),
//             tokenAmounts: new Client.EVMTokenAmount[](0),
//             extraArgs: "",
//             feeToken: address(0)
//         });

//         uint256 fee = IRouterClient(i_router).getFee(ethereumChainSelector, message);
//         IRouterClient(i_router).ccipSend{value: fee}(ethereumChainSelector, message);
//     }

//     /**
//      * Receives the entire Round from ethereum. Saves pending balances and the total pending amount.
//      */
//     function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal {
//         uint64 chainSelector = any2EvmMessage.chainSelector; // fetch the source chain identifier (aka selector)
//         address sender = abi.decode(any2EvmMessage.sender, (address)); // abi-decoding of the sender address

//         require(chainSelector == ethereumChainSelector, "Message from invalid chain");
//         require(sender == receiverInEthereum, "Invalid sender");

//         Round memory incommingRound = abi.decode(any2EvmMessage.data, (Round));

//         currentRound = incommingRound.roundId;
//         rounds[currentRound] = incommingRound;
//         currentRoundTotalBalance = 0;

//         for (uint256 i = 0; i < incommingRound.participants.length; i++) {
//             pendingBalances[incommingRound.participants[i]] += incommingRound.balances[incommingRound.participants[i]];
//             currentRoundTotalBalance += incommingRound.balances[incommingRound.participants[i]];
//         }
//     }
// }

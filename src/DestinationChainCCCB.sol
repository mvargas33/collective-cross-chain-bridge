// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Withdraw} from "./utils/Withdraw.sol";

contract DestinationChainCCCB is CCIPReceiver, Withdraw {
    using SafeERC20 for IERC20;

    enum ContractState {
        OPEN,
        BLOCKED
    }

    struct Round {
        uint256 roundId;
        uint256[] balances;
        address[] participants;
    }

    ContractState public contractState;
    address public tokenAddress;
    uint64 public destinationChainSelector;
    address public destinationContract;

    uint256 currentRound;
    uint256 currentTokenAmount;
    mapping(address => uint256) pendingBalances;
    mapping(uint256 => Round) rounds;
    mapping(uint256 => bool) successfulRounds;

    constructor(address _router, address _tokenAddress, uint64 _destinationChainSelector, address _destinationContract)
        CCIPReceiver(_router)
    {
        contractState = ContractState.BLOCKED;
        tokenAddress = _tokenAddress;
        destinationChainSelector = _destinationChainSelector;
        destinationContract = _destinationContract;
        currentRound = 0;
        currentTokenAmount = 0;
    }

    receive() external payable {}

    /**
     * Receives the entire Round from the source chain. Saves the Round, pending balances and the total pending amount.
     */
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        uint64 chainSelector = any2EvmMessage.sourceChainSelector;
        address sender = abi.decode(any2EvmMessage.sender, (address));

        require(chainSelector == destinationChainSelector, "Message from invalid chain");
        require(sender == destinationContract, "Invalid sender");

        Round memory newRound = abi.decode(any2EvmMessage.data, (Round));
        require(newRound.roundId == currentRound, "Corrupted contract");

        rounds[currentRound] = newRound;
        currentRound = newRound.roundId;
        currentTokenAmount = 0;

        for (uint256 i = 0; i < newRound.participants.length; i++) {
            pendingBalances[newRound.participants[i]] = newRound.balances[i];
            currentTokenAmount += newRound.balances[i];
        }

        contractState == ContractState.OPEN;
    }

    /**
     * Send all pendingBalances to participants of this round. Then lock this contract again until
     * the next round.
     */
    function sendBalances() public {
        require(contractState == ContractState.OPEN, "Wait for the next round");
        require(msg.sender != address(0));
        require(IERC20(tokenAddress).balanceOf(address(this)) >= currentTokenAmount, "Corrupted contract");

        for (uint256 i = 0; i < rounds[currentRound].participants.length; i++) {
            address to = rounds[currentRound].participants[i];
            uint256 value = pendingBalances[to];

            IERC20(tokenAddress).safeTransfer(to, value);

            currentTokenAmount -= pendingBalances[to];
            pendingBalances[to] = 0;
        }

        require(currentTokenAmount == 0, "Correupted contract: some asset was not send");
        successfulRounds[currentRound] = true;

        _sendMessage();

        contractState == ContractState.BLOCKED;
    }

    /**
     * Once all balances have been distributed, sends an ACK to the source chain contract of the {currentRound}
     */
    function _sendMessage() internal returns (bytes32) {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destinationContract),
            data: abi.encode(currentRound),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 200_000, strict: false})),
            feeToken: address(0)
        });

        IRouterClient router = IRouterClient(this.getRouter());
        uint256 fees = router.getFee(destinationChainSelector, message);
        return router.ccipSend{value: fees}(destinationChainSelector, message);
    }
}
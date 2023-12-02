// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Withdraw} from "./utils/Withdraw.sol";

contract SourceChainCCCB is CCIPReceiver, Withdraw {
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
    uint256 public nativeTokenTax;

    uint256 currentRound;
    uint256 currentTokenAmount;
    mapping(address => uint256) balances;
    mapping(uint256 => Round) rounds;
    mapping(uint256 => bool) successfulRounds;

    constructor(address _router, address _tokenAddress, uint64 _destinationChainSelector, address _destinationContract, uint256 _nativeTokenTax) CCIPReceiver(_router) {
      contractState = ContractState.OPEN;
      tokenAddress = _tokenAddress;
      destinationChainSelector = _destinationChainSelector;
      destinationContract = _destinationContract;
      nativeTokenTax = _nativeTokenTax;
      currentRound = 0;
      currentTokenAmount = 0;
    }

    receive() external payable {}

    /**
     * Deposit {tokenAddress} token via transferFrom. Then records the amount in local structs.
     * You cannot participate twice in the same round, for the sake of simplicity. An approve
     * must occur beforehand for at least {tokenAmount}.
     */
    function deposit(uint256 tokenAmount) public payable {
        require(contractState == ContractState.OPEN, "Wait for the next round");
        require(msg.sender != address(0));
        require(msg.value >= nativeTokenTax, "Insuffitient tax");
        require(balances[msg.sender] == 0, "You already entered this round, wait for the next one");
        require(tokenAmount > 0, "Amount should be greater than zero");

        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), tokenAmount);

        rounds[currentRound].participants.push(msg.sender);
        rounds[currentRound].balances.push(tokenAmount);

        balances[msg.sender] = tokenAmount;
        currentTokenAmount += tokenAmount;
    }

    /**
     * Anyone can call this function to end the current round and bridge the tokens in the contract.
     * The caller gets all native token present in the contract, collected through the collective
     * {nativeTokenTax} that each participant gave over time. Blocks the contract until the message
     * of sucess arrives from the destination chain.
     */
    function bridge() external returns (bytes32 messageId) {
        require(contractState == ContractState.OPEN, "Wait for the next round");
        require(msg.sender != address(0));
        require(currentTokenAmount > 0, "No participants yet");
        require(IERC20(tokenAddress).balanceOf(address(this)) >= currentTokenAmount, "Corrupted contract");
        require(rounds[currentRound].balances.length == rounds[currentRound].participants.length, "Corrupted contract");

        // Bridge tokens with current Round data
        contractState = ContractState.BLOCKED;
        messageId = _sendRoundToPolygon();

        // Pay back for the call
        (bool success, ) = payable(msg.sender).call{ value: address(this).balance }("");
        require(success, "Transfer ETH in contract failed");

        return messageId;
    }

    /**
     * Sends the {tokenAddress} and {currentRound} Round to destination chain via CCIP.
     * Returns messageId for tracking purposes.
     */
    function _sendRoundToPolygon() internal returns (bytes32) {
        Client.EVMTokenAmount memory tokenAmount = Client.EVMTokenAmount({token: address(tokenAddress), amount: currentTokenAmount});
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = tokenAmount;

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destinationContract),
            data: abi.encode(rounds[currentRound]),
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
              Client.EVMExtraArgsV1({gasLimit: 2_000_000, strict: false})
            ),
            feeToken: address(0) // Pay in native
        });

        IRouterClient router = IRouterClient(this.getRouter());
        uint256 fees = router.getFee(destinationChainSelector, message);

        return router.ccipSend{value: fees}(destinationChainSelector, message);
    }

    /**
     * Triggered by destination contract in destination chain, this function act as an ACK
     * that the bridged balances were succesfully distributed in that chain. Resets this
     * contract state and pass to the next round.
     */
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        // bytes32 messageId = any2EvmMessage.messageId;
        uint64 sourceChainSelector = any2EvmMessage.sourceChainSelector; // fetch the source chain identifier (aka selector)
        address sender = abi.decode(any2EvmMessage.sender, (address)); // abi-decoding of the sender address

        require(sourceChainSelector == destinationChainSelector, "Message from invalid chain");
        require(sender == destinationContract, "Invalid sender");

        uint256 roundIdProcessed = abi.decode(any2EvmMessage.data, (uint256)); // abi-decoding of the sent string message

        require(roundIdProcessed == currentRound, "Corrupted contract");

        _nextRound();
    }

    /**
     * Reset local balances, mark the current round as successful, pass to the next round,
     * and finally opens the contract again.
     */
    function _nextRound() internal {
      successfulRounds[currentRound] = true;

      for (uint256 i = 0; i < rounds[currentRound].participants.length; i++) {
        balances[rounds[currentRound].participants[i]] = 0;
      }

      currentRound += 1;
      currentTokenAmount = 0;
      contractState = ContractState.OPEN;
    }
}

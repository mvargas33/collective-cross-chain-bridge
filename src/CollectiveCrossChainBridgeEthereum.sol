// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Withdraw} from "./utils/Withdraw.sol";

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES HARDCODED VALUES FOR CLARITY.
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
contract CollectiveCrossChainBridgeEthereum is CCIPReceiver, Withdraw {
    using SafeERC20 for IERC20;

    enum ContractState {
        OPEN,
        BLOCKED
    }

    address immutable i_link = 0x779877A7B0D9E8603169DdbD7836e478b4624789; // LINK Sepolia
    uint64 immutable polygonChainSelector = 12532609583862916517; // Polygon Mumbai
    IERC20 immutable tokenAddress = IERC20(0x1a93Dd2Ff0308F0Ae65a94aDC191E8A43d2e978c); // Only token allowed to bridge
    address immutable receiverInPolygon = 0x1a93Dd2Ff0308F0Ae65a94aDC191E8A43d2e978c; // polygon contract address. TODO: Add setter/getter onlyOwner, the burn keys
    uint256 immutable depositTaxInNativeToken = 0.0001 ether;

    ContractState private contractState = ContractState.OPEN;

    struct Round {
        uint256 roundId;
        mapping(address => uint256) balances;
        address[] participants;
    }

    struct EncodableRound {
      uint256 roundId;
      uint256[] balances;
      address[] participants;
    }

    mapping(uint256 => Round) rounds;
    uint256 currentRound;

    mapping(uint256 => bool) successfulRounds;

    LinkTokenInterface linkToken;

    constructor(address _router, address link) CCIPReceiver(_router) {
        linkToken = LinkTokenInterface(link);
        currentRound = 0;
        rounds[0].roundId = 0;
    }

    receive() external payable {}

    function deposit(uint256 amount) public payable {
        require(contractState == ContractState.OPEN, "Wait for the next round");
        require(msg.sender != address(0));
        require(msg.value >= depositTaxInNativeToken, "Insuffitient tax");

        tokenAddress.safeTransferFrom(msg.sender, address(this), amount);

        if (rounds[currentRound].balances[msg.sender] == 0) {
            rounds[currentRound].participants.push(msg.sender);
        }

        rounds[currentRound].balances[msg.sender] += amount;
    }

    function bridge() external returns (bytes32) {
        require(contractState == ContractState.OPEN, "Wait for the next round");
        require(msg.sender != address(0));

        contractState = ContractState.BLOCKED;

        bytes32 messageId = _sendRoundToPolygon();

        (bool success, ) = payable(msg.sender).call{ value: address(this).balance }(""); // Whoever bridge this rounds gets the eth in the contract
        require(success, "Transfer ETH in contract failed");

        return messageId;
    }

    function _sendRoundToPolygon() internal returns (bytes32 messageId) {
        uint256 roundId = rounds[currentRound].roundId;
        address[] memory participants = new address[](rounds[currentRound].participants.length);
        uint256[] memory balances = new uint256[](rounds[currentRound].participants.length);
        
        for (uint256 j = 0; j < rounds[currentRound].participants.length; j++) {
          participants[j] = rounds[currentRound].participants[j];
          balances[j] = (rounds[currentRound].balances[participants[j]]);
        }

        EncodableRound memory roundToSend = EncodableRound(
          roundId,
          balances,
          participants
        );

        Client.EVMTokenAmount memory tokenAmount = Client.EVMTokenAmount({token: address(tokenAddress), amount: 0}); // TODO: define total amouny

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = tokenAmount;

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverInPolygon),
            data: abi.encode(roundToSend),
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
              Client.EVMExtraArgsV1({gasLimit: 2_000_000, strict: false}) // Additional arguments, setting gas limit and non-strict sequency mode
            ),
            feeToken: address(0) // or address(linkToken)
        });

        IRouterClient router = IRouterClient(this.getRouter());

        uint256 fees = router.getFee(polygonChainSelector, message);
        linkToken.approve(address(router), fees);

        IERC20(tokenAddress).approve(address(router), 0); // TODO: Replace amount (total between participants)

        messageId = router.ccipSend{value: fees}(polygonChainSelector, message); // TODO: Decide to use eth or link

        return messageId;
    }

    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        // bytes32 messageId = any2EvmMessage.messageId;
        uint64 sourceChainSelector = any2EvmMessage.sourceChainSelector; // fetch the source chain identifier (aka selector)
        address sender = abi.decode(any2EvmMessage.sender, (address)); // abi-decoding of the sender address

        require(sourceChainSelector == polygonChainSelector, "Message from invalid chain");
        require(sender == receiverInPolygon, "Invalid sender");

        uint256 roundIdProcessed = abi.decode(any2EvmMessage.data, (uint256)); // abi-decoding of the sent string message

        successfulRounds[roundIdProcessed] = true;
        currentRound += 1;
        contractState = ContractState.OPEN;
    }
}

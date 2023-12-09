// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ISourceChainCCCB} from "./interfaces/ISourceChainCCCB.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Withdraw} from "./utils/Withdraw.sol";
import {TaxManager} from "./TaxManager.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SourceChainCCCB is ISourceChainCCCB, CCIPReceiver, TaxManager {
    using SafeERC20 for IERC20;

    ContractState public contractState;
    address public tokenAddress;
    uint64 public destinationChainSelector;
    address public destinationContract;

    uint256 currentRoundId;
    address[] public participants;
    mapping(address => uint256) public balances;
    mapping(uint256 => bool) public successfulRounds;

    constructor(
        address _router,
        uint64 _destinationChainSelector,
        uint64 _currentChainSelector,
        address _owner,
        address _tokenAddress
    ) CCIPReceiver(_router) TaxManager(_currentChainSelector, _owner) {
        contractState = ContractState.OPEN;
        destinationChainSelector = _destinationChainSelector;
        currentRoundId = 0;
        tokenAddress = _tokenAddress;
        IERC20(tokenAddress).approve(address(_router), type(uint256).max);
    }

    receive() external payable {}

    /**
     * Setter to use just after contract deployment
     */
    function setDestinationContract(address _destinationContract) external onlyOwner {
        destinationContract = _destinationContract;
    }

    /**
     * Deposit {tokenAddress} token via transferFrom. Then records the amount in local structs.
     * You cannot participate twice in the same round, for the sake of simplicity. An approve
     * must occur beforehand for at least {tokenAmount}.
     */
    function deposit(uint256 tokenAmount) public payable {
        require(contractState == ContractState.OPEN, "Wait for the next round");
        require(msg.value >= getDepositTax(), "Insuffitient tax");
        require(balances[msg.sender] == 0, "You already entered this round, wait for the next one");
        require(tokenAmount > 0, "Amount should be greater than zero");

        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), tokenAmount);

        participants.push(msg.sender);
        balances[msg.sender] = tokenAmount;
    }

    /**
     * Anyone can call this function to end the current round and bridge the tokens in the contract.
     * The caller gets all native token present in the contract, collected through the collective
     * {depositTax} that each participant gave over time. Blocks the contract until the message
     * of sucess arrives from the destination chain.
     */
    function bridge() public returns (bytes32 messageId, uint256 fees) {
        require(contractState == ContractState.OPEN, "Wait for the next round");
        require(participants.length > 0, "No participants yet");
        // require(address(this).balance >= getLastDestinationChainFees(), "Not enough gas to call ccip");

        // Bridge tokens with current Round data
        contractState = ContractState.BLOCKED;
        (messageId, fees) = _bridgeBalances();

        // Pay rewards to protocol and caller
        _payRewards();

        return (messageId, fees);
    }

    /**
     * Sends the {tokenAddress} and {currentRound} Round to destination chain via CCIP.
     * Returns messageId for tracking purposes.
     */
    function _bridgeBalances() internal returns (bytes32 messageId, uint256 fees) {
        (Round memory currentRound, uint256 currentTokenAmount) = _getCurrentRoundAndTokenAmount();
        require(IERC20(tokenAddress).balanceOf(address(this)) >= currentTokenAmount, "Corrupted contract");

        Client.EVMTokenAmount memory tokenAmount =
            Client.EVMTokenAmount({token: address(tokenAddress), amount: currentTokenAmount});
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = tokenAmount;

        IRouterClient router = IRouterClient(this.getRouter());

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destinationContract),
            data: abi.encode(currentRound),
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 200_000, strict: false})),
            feeToken: address(0) // Pay in native
        });

        fees = router.getFee(destinationChainSelector, message);
        messageId = router.ccipSend{value: fees}(destinationChainSelector, message);
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

        require(roundIdProcessed == currentRoundId, "Corrupted contract");

        _nextRound();
    }

    /**
     * Reset local balances, mark the current round as successful, pass to the next round,
     * and finally opens the contract again.
     */
    function _nextRound() internal {
        successfulRounds[currentRoundId] = true;

        for (uint256 i = 0; i < participants.length;) {
            balances[participants[i]] = 0;
            unchecked {
                i++;
            }
        }

        delete participants;

        currentRoundId += 1;
        contractState = ContractState.OPEN;
    }

    /**
     * Getters
     */

    function getContractState() external view returns (ContractState) {
        return contractState;
    }

    function getTokenAddress() external view returns (address) {
        return tokenAddress;
    }

    function getDestinationChainSelector() external view returns (uint64) {
        return destinationChainSelector;
    }

    function getDestinationContract() external view returns (address) {
        return destinationContract;
    }

    function getCurrentRoundId() external view returns (uint256) {
        return currentRoundId;
    }

    function getBalancesAsArray() public view returns (uint256[] memory balancesArray) {
        balancesArray = new uint256[](participants.length);

        for (uint256 i = 0; i < participants.length;) {
            balancesArray[i] = balances[participants[i]];
            unchecked {
                i++;
            }
        }
    }

    function getCurrentTokenAmount() public view returns (uint256 currentTokenAmount) {
        currentTokenAmount = 0;

        for (uint256 i = 0; i < participants.length;) {
            currentTokenAmount += balances[participants[i]];
            unchecked {
                i++;
            }
        }
    }

    function getBalances(address user) public view returns (uint256) {
        return balances[user];
    }

    function getCurrentRound() public view returns (Round memory currentRound) {
        uint256[] memory balancesArray = getBalancesAsArray();

        currentRound = Round({roundId: currentRoundId, balances: balancesArray, participants: participants});
    }

    function _getCurrentRoundAndTokenAmount()
        internal
        view
        returns (Round memory currentRound, uint256 currentTokenAmount)
    {
        currentTokenAmount = 0;
        uint256[] memory balancesArray = new uint256[](participants.length);

        for (uint16 i = 0; i < participants.length;) {
            currentTokenAmount += balances[participants[i]];
            balancesArray[i] = balances[participants[i]];
            unchecked {
                i++;
            }
        }

        currentRound = Round({roundId: currentRoundId, balances: balancesArray, participants: participants});
    }

    function isRoundSuccessful(uint256 roundId) external view returns (bool) {
        return successfulRounds[roundId];
    }

    function getContractTokenBalance() external view returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this));
    }
}

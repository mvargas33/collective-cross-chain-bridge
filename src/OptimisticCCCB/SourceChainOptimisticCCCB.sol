// SPDX-License-Identifier: Apache License 2.0
pragma solidity 0.8.20;

import {ISourceChainOptimisticCCCB} from "../interfaces/OptimisticCCCB/ISourceChainOptimisticCCCB.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Withdraw} from "../utils/Withdraw.sol";
import {TaxManager} from "../TaxManager.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SourceChainOptimisticCCCB is ISourceChainOptimisticCCCB, TaxManager {
    using SafeERC20 for IERC20;

    address public tokenAddress;
    uint64 public destinationChainSelector;
    address public destinationContract;
    uint256 public destinationGasLimit;
    address public localRouter;

    uint256 currentRoundId;
    FullRound[] public rounds;

    constructor(
        address _router,
        uint64 _destinationChainSelector,
        uint64 _currentChainSelector,
        address _owner,
        address _tokenAddress,
        address _localRouter
    ) TaxManager(_currentChainSelector, _owner) {
        destinationChainSelector = _destinationChainSelector;
        currentRoundId = 0;
        tokenAddress = _tokenAddress;
        destinationGasLimit = 2_000_000;
        localRouter = _localRouter;
        
        FullRound storage newRound = rounds.push();
        newRound.roundId = 0;
        newRound.participants = new address[](0);

        IERC20(tokenAddress).approve(address(_router), type(uint256).max);
    }

    receive() external payable {}

    /**
     * Setter to use just after contract deployment
     */

    function setTokenAddress(address _tokenAddress) external onlyOwner {
        tokenAddress = _tokenAddress;
    }

    function setDestinationContract(address _destinationContract) external onlyOwner {
        destinationContract = _destinationContract;
    }

    function setDestinationGasLimit(uint256 _destinationGasLimit) external onlyOwner {
        destinationGasLimit = _destinationGasLimit;
    }

    /**
     * Deposit {tokenAddress} token via transferFrom. Then records the amount in local structs.
     * You cannot participate twice in the same round, for the sake of simplicity. An approve
     * must occur beforehand for at least {tokenAmount}.
     */
    function deposit(uint256 tokenAmount) public payable {
        require(msg.value >= getDepositTax(), "Insuffitient tax");
        require(rounds[currentRoundId].balances[msg.sender] == 0, "You already entered this round, wait for the next one");
        require(tokenAmount > 0, "Amount should be greater than zero");

        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), tokenAmount);

        rounds[currentRoundId].participants.push(msg.sender);
        rounds[currentRoundId].balances[msg.sender] = tokenAmount;

        emit DepositTaxPaid(msg.sender, msg.value);
        emit UserDeposit(msg.sender, tokenAmount, currentRoundId);
    }

    /**
     * Same as deposit, but for someone else
     */
    function depositTo(address _recipient, uint256 tokenAmount) public payable {
        require(msg.value >= getDepositTax(), "Insuffitient tax");
        require(rounds[currentRoundId].balances[_recipient] == 0, "You already entered this round, wait for the next one");
        require(tokenAmount > 0, "Amount should be greater than zero");

        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), tokenAmount);

        rounds[currentRoundId].participants.push(_recipient);
        rounds[currentRoundId].balances[_recipient] = tokenAmount;

        emit DepositTaxPaid(_recipient, msg.value);
        emit UserDeposit(_recipient, tokenAmount, currentRoundId);
    }

    /**
     * Anyone can call this function to end the current round and bridge the tokens in the contract.
     * The caller gets all native token present in the contract, collected through the collective
     * {depositTax} that each participant gave over time. Blocks the contract until the message
     * of sucess arrives from the destination chain.
     */
    function bridge() public returns (bytes32 messageId, uint256 fees) {
        require(rounds[currentRoundId].participants.length > 0, "No participants yet");
        // require(address(this).balance >= getLastDestinationChainFees(), "Not enough gas to call ccip");

        // Bridge tokens with current Round data
        (messageId, fees) = _bridgeBalances();

        // Pay rewards to protocol and caller
        _payRewards();
        
        currentRoundId += 1;

        FullRound storage newRound = rounds.push();
        newRound.roundId = 0;
        newRound.participants = new address[](0);

        return (messageId, fees);
    }

    /**
     * Sends the {tokenAddress} and {currentRound} Round to destination chain via CCIP.
     * Returns messageId for tracking purposes.
     */
    function _bridgeBalances() internal returns (bytes32 messageId, uint256 fees) {
        (SimpleRound memory currentRound, uint256 currentTokenAmount) = _getCurrentSimpleRoundAndTokenAmount();
        // require(IERC20(tokenAddress).balanceOf(address(this)) >= currentTokenAmount, "Corrupted contract");

        Client.EVMTokenAmount memory tokenAmount =
            Client.EVMTokenAmount({token: address(tokenAddress), amount: currentTokenAmount});
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = tokenAmount;

        IRouterClient router = IRouterClient(localRouter);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(destinationContract),
            data: abi.encode(currentRound),
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: destinationGasLimit, strict: false})),
            feeToken: address(0) // Pay in native
        });

        fees = router.getFee(destinationChainSelector, message);
        messageId = router.ccipSend{value: fees}(destinationChainSelector, message);

        emit RoundBridged(currentRoundId, currentRound.participants, currentRound.balances, currentTokenAmount, fees, messageId);
    }

    /**
     * Getters
     */

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
        balancesArray = new uint256[](rounds[currentRoundId].participants.length);

        for (uint256 i = 0; i < rounds[currentRoundId].participants.length;) {
            balancesArray[i] = rounds[currentRoundId].balances[rounds[currentRoundId].participants[i]];
            unchecked {
                i++;
            }
        }
    }

    function getCurrentTokenAmount() public view returns (uint256 currentTokenAmount) {
        currentTokenAmount = 0;

        for (uint256 i = 0; i < rounds[currentRoundId].participants.length;) {
            currentTokenAmount += rounds[currentRoundId].balances[rounds[currentRoundId].participants[i]];
            unchecked {
                i++;
            }
        }
    }

    function getBalances(address user) public view returns (uint256) {
        return rounds[currentRoundId].balances[user];
    }

    function getCurrentRound() public view returns (SimpleRound memory currentRound) {
        uint256[] memory balancesArray = getBalancesAsArray();

        currentRound = SimpleRound({roundId: currentRoundId, balances: balancesArray, participants: rounds[currentRoundId].participants});
    }

    function _getCurrentSimpleRoundAndTokenAmount()
        internal
        view
        returns (SimpleRound memory currentRound, uint256 currentTokenAmount)
    {
        currentTokenAmount = 0;
        uint256[] memory balancesArray = new uint256[](rounds[currentRoundId].participants.length);
        uint256 participantBalance = 0;

        for (uint16 i = 0; i < rounds[currentRoundId].participants.length;) {
            participantBalance = rounds[currentRoundId].balances[rounds[currentRoundId].participants[i]];
            currentTokenAmount += participantBalance;
            balancesArray[i] = participantBalance;
            unchecked {
                i++;
            }
        }

        currentRound = SimpleRound({roundId: currentRoundId, balances: balancesArray, participants: rounds[currentRoundId].participants});
    }

    function isRoundSuccessful(uint256 roundId) external view returns (bool) {
        return roundId < currentRoundId;
    }

    function getContractTokenBalance() external view returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this));
    }
}

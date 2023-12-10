// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test, console2} from "forge-std/Test.sol";
import {ExposedDestinationChainCCCB} from "./utils/ExposedDestinationChainCCCB.sol";
import {IDestinationChainCCCB} from "../src/interfaces/IDestinationChainCCCB.sol";
import {BasicTokenSender} from "../src/BasicTokenSender.sol";
import {Utils} from "./utils/Utils.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract DestinationChainCCCBTest is Test, Utils {
    ExposedDestinationChainCCCB public bridge;
    address alice = vm.addr(0xa11ce);
    address bob = vm.addr(0xb0b);
    address carl = vm.addr(0xca41);
    address sourceContractAddress = vm.addr(0xeeaaff00);
    address manager = vm.addr(0x81273);

    function setUp() public {
        vm.createSelectFork("avalancheFuji");
        bridge = new ExposedDestinationChainCCCB(routerAvalancheFuji, chainIdEthereumSepolia, manager, ccipBnMAvalancheFuji);

        vm.prank(manager);
        bridge.setDestinationContract(sourceContractAddress);

        vm.label(routerAvalancheFuji, "Router Avalanche Fuji");
        vm.label(ccipBnMAvalancheFuji, "BnM token");
    }

    function getTestAny2EvmMessage()
        public
        view
        returns (Client.Any2EVMMessage memory any2EvmMessage, uint256 amountReceived)
    {
        // Simulate a token reception
        uint256 roundId = 0;
        uint256[] memory balances = new uint256[](3);
        balances[0] = 1e18;
        balances[1] = 7e18;
        balances[2] = 2e18;
        address[] memory participants = new address[](3);
        participants[0] = alice;
        participants[1] = bob;
        participants[2] = carl;

        IDestinationChainCCCB.Round memory sourceChainRound =
            IDestinationChainCCCB.Round({roundId: roundId, balances: balances, participants: participants});

        amountReceived = 10e18;
        Client.EVMTokenAmount memory tokenAmount =
            Client.EVMTokenAmount({token: ccipBnMAvalancheFuji, amount: amountReceived});
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = tokenAmount;

        any2EvmMessage = Client.Any2EVMMessage({
            messageId: keccak256("messageId"),
            sourceChainSelector: chainIdEthereumSepolia,
            sender: abi.encode(sourceContractAddress),
            data: abi.encode(sourceChainRound),
            destTokenAmounts: tokenAmounts
        });

        return (any2EvmMessage, amountReceived);
    }

    /**
     * Receive tokens and set data in contract
     */
    function test_ccipReceive() public {
        (Client.Any2EVMMessage memory any2EvmMessage, uint256 amountReceived) = getTestAny2EvmMessage();
        IDestinationChainCCCB.Round memory round = abi.decode(any2EvmMessage.data, (IDestinationChainCCCB.Round));

        deal(ccipBnMAvalancheFuji, address(bridge), amountReceived);

        // Now trigger _ccipReceive
        vm.prank(routerAvalancheFuji);
        bridge.ccipReceive(any2EvmMessage);

        // Check that the round was copied, and pending balances are ok
        assertEq(IERC20(bridge.getTokenAddress()).balanceOf(address(bridge)), amountReceived);
        assertEq(bridge.getCurrentRoundId(), round.roundId);
        assertEq(bridge.getRound(round.roundId).roundId, round.roundId);
        assertEq(bridge.getRound(round.roundId).balances, round.balances);
        assertEq(bridge.getRound(round.roundId).participants, round.participants);
        assertEq(bridge.getCurrentTokenAmount(), amountReceived);
        assertEq(bridge.getPendingBalances(alice), 1e18);
        assertEq(bridge.getPendingBalances(bob), 7e18);
        assertEq(bridge.getPendingBalances(carl), 2e18);
        assertTrue(bridge.getContractState() == IDestinationChainCCCB.ContractState.OPEN);
        assertEq(bridge.isRoundSuccessful(round.roundId), false);
    }

    /**
     * Test that the funds distribution is performed well and is final.
     */
    function test_distributeFunds() public {
        (Client.Any2EVMMessage memory any2EvmMessage, uint256 amountReceived) = getTestAny2EvmMessage();
        IDestinationChainCCCB.Round memory round = abi.decode(any2EvmMessage.data, (IDestinationChainCCCB.Round));
        deal(ccipBnMAvalancheFuji, address(bridge), amountReceived);
        deal(address(bridge), 100e18);
        vm.prank(routerAvalancheFuji);
        bridge.ccipReceive(any2EvmMessage);

        // Now distribute funds
        uint256 startBalance = IERC20(bridge.getTokenAddress()).balanceOf(address(bridge));

        vm.prank(carl); // Anyone can call it
        bridge.distributeFunds();

        uint256 finalBalance = IERC20(bridge.getTokenAddress()).balanceOf(address(bridge));

        assertEq(startBalance - finalBalance, amountReceived);
        assertEq(finalBalance, 0);
        assertEq(bridge.getCurrentRoundId(), round.roundId);
        assertEq(bridge.getCurrentTokenAmount(), 0);
        assertEq(IERC20(bridge.getTokenAddress()).balanceOf(alice), 1e18);
        assertEq(IERC20(bridge.getTokenAddress()).balanceOf(bob), 7e18);
        assertEq(IERC20(bridge.getTokenAddress()).balanceOf(carl), 2e18);
        assertEq(bridge.getPendingBalances(alice), 0);
        assertEq(bridge.getPendingBalances(bob), 0);
        assertEq(bridge.getPendingBalances(carl), 0);
        assertTrue(bridge.getContractState() == IDestinationChainCCCB.ContractState.BLOCKED);
        assertEq(bridge.isRoundSuccessful(round.roundId), true);
    }
}

// SPDX-License-Identifier: Apache License 2.0
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test, console} from "forge-std/Test.sol";
import {SourceChainCCCB} from "../src/SourceChainCCCB.sol";
import {BasicTokenSender} from "../src/BasicTokenSender.sol";
import {Utils} from "./utils/Utils.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract SourceChainCCCBTest is Test, Utils {
    SourceChainCCCB public bridge;
    BasicTokenSender public basicBridge;
    address alice = vm.addr(0xa11ce0000000dead);
    address bob = vm.addr(0xb0b0000000dead);
    address manager = vm.addr(0x81273);

    function setUp() public {
        vm.createSelectFork("ethereumSepolia");
        bridge = new SourceChainCCCB(
            routerEthereumSepolia, chainIdAvalancheFuji, chainIdEthereumSepolia, manager, ccipBnMEthereumSepolia
        );
        vm.startPrank(manager);
        // bridge.setTokenAddress(ccipBnMEthereumSepolia);
        bridge.setDestinationContract(address(alice));
        vm.stopPrank();

        basicBridge = new BasicTokenSender(routerEthereumSepolia, linkEthereumSepolia);

        vm.label(routerEthereumSepolia, "Router sepolia");
        vm.label(ccipBnMEthereumSepolia, "BnM token");
        vm.label(linkEthereumSepolia, "LINK Sepolia");
    }

    /**
     * One deposit cost 83_669 gas for 1 user [safeTransferFrom + push in array + write in mapping]
     * One brige for 1 user costs 303_600. But for 100 users it costs
     */
    function test_deposit_and_bridge() public {
        uint256 despoitTax = bridge.getDepositTax();
        uint256 tokenAmount = 10e18;
        deal(alice, despoitTax);
        deal(ccipBnMEthereumSepolia, alice, tokenAmount);

        vm.startPrank(alice);
        IERC20(ccipBnMEthereumSepolia).approve(address(bridge), tokenAmount);
        bridge.deposit{value: despoitTax}(tokenAmount);
        vm.stopPrank();

        assertEq(IERC20(ccipBnMEthereumSepolia).balanceOf(address(bridge)), tokenAmount);
        assertEq(IERC20(ccipBnMEthereumSepolia).balanceOf(alice), 0);
        assertEq(alice.balance, 0); // Use all tax

        (uint256 protocolReward, uint256 callerReward) = bridge.getEstimatedRewards();
        uint256 previousBobBalance = bob.balance;

        deal(address(bridge), 500_000_000_000_000_000); // Give some eth to be able to call destination chain
        
        vm.startPrank(bob);
        bridge.bridge();
        bridge.claimRewards(); // Not enough for rewards
        vm.stopPrank();

        vm.prank(bridge.owner());
        bridge.claimProtocolRewards();

        if (protocolReward == 0) {
            assertEq(address(bridge.owner()).balance, 0);
        } else {
            assertGe(address(bridge.owner()).balance, (85 * protocolReward) / 100);
        }

        if (callerReward == 0) {
            assertEq(bob.balance - previousBobBalance, 0);
        } else {
            assertGe(bob.balance - previousBobBalance, (85 * callerReward) / 100);
        }

        assertEq(IERC20(ccipBnMEthereumSepolia).balanceOf(address(bridge)), 0);
    }

    /**
     * forge-config: default.fuzz.runs = 2
     * forge-config: default.fuzz.max-test-rejects = 0
     */
    function test_collectiveDeposit() public {
        // vm.assume(n_users > 5);
        uint16 n_users = 14;
        uint256 initialContractbalance = address(bridge).balance;

        uint256 tokenAmount = 10e18;
        uint256 tax = bridge.getDepositTax();

        for (uint256 i = 0; i < n_users; i++) {
            address user = vm.addr(100 + i);

            deal(user, tax);
            deal(ccipBnMEthereumSepolia, user, tokenAmount);

            vm.startPrank(user);
            IERC20(ccipBnMEthereumSepolia).approve(address(bridge), tokenAmount);
            bridge.deposit{value: tax}(tokenAmount);
            vm.stopPrank();
        }

        assertEq(IERC20(ccipBnMEthereumSepolia).balanceOf(address(bridge)), n_users * tokenAmount);
        assertEq(address(bridge).balance, initialContractbalance + (n_users * tax));

        uint256 previousOwnerBalance = address(bridge.owner()).balance;
        uint256 previousBobBalance = bob.balance;
        uint256 previousContractbalance = address(bridge).balance;
        (uint256 protocolReward, uint256 callerReward) = bridge.getEstimatedRewards();

        if (previousContractbalance > bridge.getDestinationChainFees()) {
            assertEq(previousContractbalance - bridge.getDestinationChainFees(), protocolReward + callerReward);
        }

        vm.startPrank(bob);
        bridge.bridge();
        bridge.claimRewards();
        vm.stopPrank();

        vm.prank(bridge.owner());
        bridge.claimProtocolRewards();

        if (protocolReward == 0) {
            assertEq(address(bridge.owner()).balance - previousOwnerBalance, 0);
        } else {
            assertGe(address(bridge.owner()).balance - previousOwnerBalance, (85 * protocolReward) / 100);
        }

        if (callerReward == 0) {
            assertEq(bob.balance - previousBobBalance, 0);
        } else {
            assertGe(bob.balance - previousBobBalance, (85 * callerReward) / 100); // Be flexible a bit
        }

        assertGe(address(bridge).balance, bridge.getDestinationChainFees()); // Save for next call
        assertEq(IERC20(ccipBnMEthereumSepolia).balanceOf(address(bridge)), 0);
    }

    /**
     * A normal vridge uses 204_626 gas for 1 user
     */
    function test_basicBridge() public {
        uint256 tokenAmount = 10e18;
        deal(ccipBnMEthereumSepolia, alice, tokenAmount);
        deal(linkEthereumSepolia, address(basicBridge), 100e18);

        Client.EVMTokenAmount memory tokenAmountToSend =
            Client.EVMTokenAmount({token: ccipBnMEthereumSepolia, amount: tokenAmount});
        Client.EVMTokenAmount[] memory tokenAmountsToSend = new Client.EVMTokenAmount[](1);
        tokenAmountsToSend[0] = tokenAmountToSend;

        deal(address(basicBridge), 10e18);

        vm.startPrank(alice);
        IERC20(ccipBnMEthereumSepolia).approve(address(basicBridge), tokenAmount);
        basicBridge.send(chainIdAvalancheFuji, alice, tokenAmountsToSend, BasicTokenSender.PayFeesIn.Native);
        vm.stopPrank();

        assertEq(IERC20(ccipBnMEthereumSepolia).balanceOf(address(basicBridge)), 0);
        assertEq(IERC20(ccipBnMEthereumSepolia).balanceOf(alice), 0);
    }
}

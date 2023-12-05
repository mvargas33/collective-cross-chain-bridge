// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test, console2} from "forge-std/Test.sol";
import {SourceChainCCCB} from "../src/SourceChainCCCB.sol";
import {BasicTokenSender} from "../src/BasicTokenSender.sol";
import {Utils} from "./utils/Utils.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract SourceChainCCCBTest is Test, Utils {
    SourceChainCCCB public bridge;
    BasicTokenSender public basicBridge;
    address alice = vm.addr(0xa11ce);
    address bob = vm.addr(0xb0b);

    function setUp() public {
        vm.createSelectFork("ethereumSepolia");
        bridge = new SourceChainCCCB(
            routerEthereumSepolia,
            ccipBnMEthereumSepolia,
            chainIdAvalancheFuji,
            address(alice), // replace with destination contract
            0 // reaplce wiht tax
        );

        basicBridge = new BasicTokenSender(routerEthereumSepolia, linkEthereumSepolia);

        vm.label(routerEthereumSepolia, "Router sepolia");
        vm.label(ccipBnMEthereumSepolia, "BnM token");
        vm.label(linkEthereumSepolia, "LINK Sepolia");
    }

    /**
     * One deposit cost 83_669 gas for 1 user [safeTransferFrom + push in array + write in mapping]
     * One brige for 1 user costs 303_600. But for 100 users it costs
     */
    function test_deposit() public {
        uint256 tokenAmount = 10e18;
        deal(ccipBnMEthereumSepolia, alice, tokenAmount);

        vm.startPrank(alice);
        IERC20(ccipBnMEthereumSepolia).approve(address(bridge), tokenAmount);
        bridge.deposit(tokenAmount);
        vm.stopPrank();

        assertEq(IERC20(ccipBnMEthereumSepolia).balanceOf(address(bridge)), tokenAmount);
        assertEq(IERC20(ccipBnMEthereumSepolia).balanceOf(alice), 0);

        deal(address(bridge), 100e18);
        vm.prank(bob);
        bridge.bridge();

        assertEq(IERC20(ccipBnMEthereumSepolia).balanceOf(address(bridge)), 0);
    }

    /**
     * 2 users = 325_904 = 162_952 per user
     * 5 users = 403_918 = 80_783 per user + value: 401045177777777
     * 10 users = 533_949 = 53_394 per user + value: 402175844444444
     * 15 users = 663984 = 44_265 per user + value: 403306511111111
     * 20 users = 794027 = 39_701 per user + value: 404437177777777
     * 30 users = 1054130 = 35_137 per user
     * 40 users = 1314259 = 32_856 per user
     * 50 users = 1574414 = 31_488 per user
     * 75 users = 2224905 = 29_665 per user
     * 100 users = 2_875_555 = 28_755 gas per user /+/ value: 0.000_422_527_844_444_444 = 0.000000_422_527_844_444 per user
     * 125 users = 3_526_361 = 28_210 per user
     * 150 users = 4_177_324 = 27_848 per user
     * 200 users = 5_479_716 = 27_398 per user
     * 300 users = 8_086_378 = 26_954 per user
     * 500 users = 13_307_200 = 26_614 per user
     * 1_000 users = ERROR 125 KB [MAX is 50 KB]
     */
    function test_colectiveDeposit() public {
        uint256 tokenAmount = 10e18;
        uint256 n = 5;

        for (uint256 i = 0; i < n; i++) {
            address user = vm.addr(100 + i);
            deal(ccipBnMEthereumSepolia, user, tokenAmount);

            vm.startPrank(user);
            IERC20(ccipBnMEthereumSepolia).approve(address(bridge), tokenAmount);
            bridge.deposit(tokenAmount);
            vm.stopPrank();
        }

        assertEq(IERC20(ccipBnMEthereumSepolia).balanceOf(address(bridge)), n * tokenAmount);

        deal(address(bridge), 1e18);

        uint256 previousBobBalance = bob.balance;
        uint256 previousContractbalance = address(bridge).balance;
        vm.prank(bob);
        (, uint256 fees) = bridge.bridge();

        assertEq(IERC20(ccipBnMEthereumSepolia).balanceOf(address(bridge)), 0);
        assertEq(bob.balance - previousBobBalance, previousContractbalance - fees); // Bob gets the reward
        assertEq(address(bridge).balance, 0); // Empty all contract balance
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

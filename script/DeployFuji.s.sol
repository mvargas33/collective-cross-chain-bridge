// SPDX-License-Identifier: Apache License 2.0
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import {Utils} from "../test/utils/Utils.sol";
import {DestinationChainCCCB} from "../src/DestinationChainCCCB.sol";

interface ICCIPToken {
    function drip(address to) external;
}

contract DeployFuji is Script, Utils {
    function deploySourceContract() external {
        uint256 senderPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(senderPrivateKey);
        address manager = vm.addr(senderPrivateKey);

        DestinationChainCCCB bridge =
            new DestinationChainCCCB(routerAvalancheFuji, chainIdEthereumSepolia, ccipBnMAvalancheFuji, manager);
        // bridge.setDestinationContract(address(alice));

        vm.stopBroadcast();
    }

    function setDestinationContract() external {
        // address sepoliaContract = '';
        // uint256 senderPrivateKey = vm.envUint("PRIVATE_KEY");
        // vm.startBroadcast(senderPrivateKey);

        // bridge.setDestinationContract(sepoliaContract);
    }
}

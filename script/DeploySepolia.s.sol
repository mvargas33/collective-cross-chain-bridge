// SPDX-License-Identifier: Apache License 2.0
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import {Utils} from "../test/utils/Utils.sol";
import {SourceChainCCCB} from "../src/SourceChainCCCB.sol";

interface ICCIPToken {
    function drip(address to) external;
}

contract DeploySepolia is Script, Utils {
    function deploySourceContract() external {
        uint256 senderPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(senderPrivateKey);
        address manager = vm.addr(senderPrivateKey);

        SourceChainCCCB bridge = new SourceChainCCCB(
            routerEthereumSepolia, chainIdAvalancheFuji, chainIdEthereumSepolia, manager, ccipBnMEthereumSepolia
        );
        // bridge.setDestinationContract(address(alice));

        vm.stopBroadcast();
    }

    function setDestinationContract() external {
      // address fujiContract = '';
      // uint256 senderPrivateKey = vm.envUint("PRIVATE_KEY");
      // vm.startBroadcast(senderPrivateKey);

      // bridge.setDestinationContract(fujiContract);
    }
}

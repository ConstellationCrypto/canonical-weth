// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {WAPE} from "../contracts/WAPE.sol";

contract DeployWAPE is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address initialOwner = msg.sender;

        address proxy = Upgrades.deployTransparentProxy(
            "WAPE.sol",
            initialOwner,
            abi.encodeCall(WAPE.initialize, ())
        );

        console.log("WAPE deployed behind TransparentUpgradeableProxy at:", proxy);

        vm.stopBroadcast();
    }
}

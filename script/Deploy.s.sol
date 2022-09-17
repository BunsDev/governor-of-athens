// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {Script} from "forge-std/Script.sol";

import {CleisthenesFactory} from "../src/CleisthenesFactory.sol";

/// @notice A very simple deployment script
contract Deploy is Script {
    /// @notice The main script entrypoint
    /// @return factory The deployed contract
    function run() external returns (CleisthenesFactory factory) {
        vm.startBroadcast();
        factory = new CleisthenesFactory();
        vm.stopBroadcast();
    }
}

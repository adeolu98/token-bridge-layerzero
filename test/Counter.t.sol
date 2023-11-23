// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {BridgeERC20} from "../src/BridgeERC20.sol";
import { LibString } from 'solady/src/utils/LibString.sol';

contract CounterTest is Test {
    BridgeERC20 token;
    using LibString for bytes;

    function setUp() public {
        token = new BridgeERC20(msg.sender, "ade", "ade", 18);
    }

    function testCheck() public {
        (bool nameCallResult, bytes memory  tokenName) = address(token)
            .staticcall(abi.encodeWithSignature("name()"));

        console.logBytes(tokenName);
        string memory toStr = tokenName.toHexStringNoPrefix();
        console.log(toStr, "here");
    }


}

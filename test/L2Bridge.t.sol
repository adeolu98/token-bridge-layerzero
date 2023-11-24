// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {BridgeERC20} from "../src/BridgeERC20.sol";
import {L2Bridge} from "../src/L2Bridge.sol";
import {L2Bridge} from "../src/L2Bridge.sol";
import "./SetUp.t.sol";
import "./L1Bridge.t.sol";

contract L2BridgeTest is L1BridgeTest {
    function testBridgeBackToL1Chain() public returns (bytes memory payload) {
        testReceiveMessageFromL1();

        //get the l2 token version of the bridged l1 token
        address l2Token = l2Bridge.L1TokenVersionOnL2(address(testToken));

        uint amountToBridge = BridgeERC20(l2Token).balanceOf(user); // send all its l2 tokens to l1
        //confirm that user indeed received tokens
        assertGt(amountToBridge, 0);

        vm.deal(user, 10 ether);

        //BRIDGE BACK TO L1
        vm.startPrank(user);
        payload = l2Bridge.sendToL1Chain{value: 1 ether}(
            l2Token,
            amountToBridge,
            layerzeroMainnetChainID
        );

        vm.stopPrank();
        //we confirm that asset is now burned by the bridge
        assertEq(BridgeERC20(l2Token).balanceOf(user), 0);
    }

    function testL2BridgeWithInsufficientBalance() public {
        testReceiveMessageFromL1();

        //get the l2 token version of the bridged l1 token
        address l2Token = l2Bridge.L1TokenVersionOnL2(address(testToken));

        uint amountToBridge = BridgeERC20(l2Token).balanceOf(user); // send all its l2 tokens to l1
        vm.deal(user, 10 ether);

        //BRIDGE BACK TO L1
        vm.expectRevert(); //expect revert due to insufficient balance
        vm.prank(user);
        l2Bridge.sendToL1Chain{value: 1 ether}(
            l2Token,
            amountToBridge + 20,
            layerzeroMainnetChainID
        );
    }

    function testLayerZeroRefundsUserOnL2() public {
        testBridgeBackToL1Chain();
        //since user had 10 ether, we used 1ether to send message,
        // which is excessive. we should check that user
        //is refunded some of the 1 ether so user bal > 9 ether
        assertGt(user.balance, 9 ether);
    }

    function testReceiveMessageFromL1() public {
        //we will simulate a scenario where bridge mints tokens upon receipt of l1 msg
        //BRIDGE FROM L1 TO L2
        bytes memory payload = L1BridgeTest.testBridgeL2Chain(); //L1 TRANSACTION

        vm.prank(lZEndPoint);
        l2Bridge.lzReceive(
            layerzeroMainnetChainID,
            abi.encodePacked(address(l1Bridge), address(l2Bridge)),
            1,
            payload
        ); //RECEIVE ON L2

        //get the l2 token version of the bridged l1 token
        address l2Token = l2Bridge.L1TokenVersionOnL2(address(testToken));

        // check that bridge bal reduced, meaning bridge sent tokens out
        assertGt(BridgeERC20(l2Token).balanceOf(address(user)), 0);
    }

    function testOnlyLZCanCallToReceiveMessageFromL1() public {
        //we will simulate a scenario where bridge mints tokens upon receipt of l1 msg
        //BRIDGE FROM L1 TO L2
        bytes memory payload = L1BridgeTest.testBridgeL2Chain(); //L1 TRANSACTION

        vm.expectRevert("LzApp: invalid endpoint caller"); //expect revert because only lz should call
        l2Bridge.lzReceive(
            layerzeroMainnetChainID,
            abi.encodePacked(address(l1Bridge), address(l2Bridge)),
            1,
            payload
        ); //RECEIVE ON L2

        //get the l2 token version of the bridged l1 token
        address l2Token = l2Bridge.L1TokenVersionOnL2(address(testToken));

        // check that bridge bal reduced, meaning bridge sent tokens out
        assertGt(BridgeERC20(l2Token).balanceOf(address(user)), 0);
    }
}

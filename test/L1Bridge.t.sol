// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {BridgeERC20} from "../src/BridgeERC20.sol";
import {L1Bridge} from "../src/L1Bridge.sol";
import {L2Bridge} from "../src/L2Bridge.sol";
import "./SetUp.t.sol";

contract L1BridgeTest is Test, SetUpTest {
    address user = makeAddr("userOne");
    uint mintAmount = 100 * 1e18;

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);
        testToken.mint(user, mintAmount);
        pauseableToken.mint(user, mintAmount);
        vm.stopPrank();
    }

    function testBridgeL2Chain() public returns (bytes memory payload) {
        uint amountToBridge = 10 * 1e18;
        vm.deal(user, 10 ether);

        vm.startPrank(user);
        testToken.approve(address(l1Bridge), amountToBridge);
        payload = l1Bridge.sendToL2Chain{value: 1 ether}(
            address(testToken),
            amountToBridge,
            layerzeroAVAXChainID
        );

        vm.stopPrank();
        //we confirm that asset is now locked in the bridge
        assertEq(testToken.balanceOf(address(l1Bridge)), amountToBridge);
    }

    function testBridgeWithInsufficientBalance() public {
        uint amountToBridge = testToken.balanceOf(user) + 1e18;
        vm.deal(user, 10 ether);

        vm.startPrank(user);
        testToken.approve(address(l1Bridge), amountToBridge);
        //expect revert because user doesnt have that much tokens
        vm.expectRevert();
        l1Bridge.sendToL2Chain{value: 1 ether}(
            address(testToken),
            amountToBridge,
            layerzeroAVAXChainID
        );

        vm.stopPrank();
        assertEq(testToken.balanceOf(address(l1Bridge)), 0);
    }

    function testLayerZeroRefundsUser() public {
        testBridgeL2Chain();
        //since user had 10 ether, we used 1ether to send message,
        // which is excessive. we should check that user
        //is refunded some of the 1 ether so user bal > 9 ether
        assertGt(user.balance, 9 ether);
    }

    function testPayloadIsCorrect() public {
        //create our payload with values we expect
        bytes memory payload = abi.encode(
            user,
            10 * 1e18, // this is amount that is bridged in testBridgeL2Chain()
            address(testToken),
            "test",
            "TST",
            18
        );
        bytes memory returnedPayload = testBridgeL2Chain();

        assertEq0(returnedPayload, payload);
    }

    function testReceiveMessageFromL2() public {
        //we will simulate a scenario where bridge sends tokens upon receipt of l2 msg
        // bridge must have liquidity to transfer tokens first
        uint amountOnBridge = 1 * 1e18;

        vm.prank(owner);
        testToken.mint(address(l1Bridge), amountOnBridge);

        bytes memory payload = abi.encode(
            user,
            amountOnBridge, //bridge should send all its tokens
            address(testToken)
        );

        vm.prank(lZEndPoint);
        l1Bridge.lzReceive(
            layerzeroAVAXChainID,
            abi.encodePacked(address(l2Bridge), address(l1Bridge)),
            1,
            payload
        );

        // check that bridge bal reduced, meaning bridge sent tokens out
        assertEq(testToken.balanceOf(address(l1Bridge)), 0);
    }

    function testOnlyLZCanCallToReceiveMessageFromL2() public {
        //we will simulate a scenario where bridge sends tokens upon receipt of l2 msg
        // bridge must have liquidity to transfer tokens first
        uint amountOnBridge = 1 * 1e18;

        vm.prank(owner);
        testToken.mint(address(l1Bridge), amountOnBridge);

        bytes memory payload = abi.encode(
            user,
            amountOnBridge, //bridge should send all its tokens
            address(testToken)
        );

        // expect revert because only the lz endpoint must be able to call
        vm.expectRevert("LzApp: invalid endpoint caller");
        l1Bridge.lzReceive(
            layerzeroAVAXChainID,
            abi.encodePacked(address(l2Bridge), address(l1Bridge)),
            1,
            payload
        );
    }
}

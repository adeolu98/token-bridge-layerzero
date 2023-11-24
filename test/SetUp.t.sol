// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {BridgeERC20} from "../src/BridgeERC20.sol";
import {L1Bridge} from "../src/L1Bridge.sol";
import {L2Bridge} from "../src/L2Bridge.sol";

contract SetUpTest is Test {
    BridgeERC20 testToken;
    L1Bridge l1Bridge;
    L2Bridge l2Bridge;

    address lZEndPoint = 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675; //LAYERZERO ENDPOINT ON MAINNET, use it for both l1 and l2 bridges for the sake of testing. tests may require actions on both chains sequentally but its hard to fork both and use them in the same test env
    uint16 layerzeroMainnetChainID = 101; // from the docs -> https://layerzero.gitbook.io/docs/technical-reference/mainnet/supported-chain-ids    uint16 layerzeroAVAXChainID = 106; // from the docs -> https://layerzero.gitbook.io/docs/technical-reference/mainnet/supported-chain-ids
    uint16 layerzeroAVAXChainID = 106;
    address owner = makeAddr("owner");

    function setUp() public virtual {
        vm.startPrank(owner);
        testToken = new BridgeERC20(msg.sender, "test", "TST", 18);
        l1Bridge = new L1Bridge(lZEndPoint);
        l2Bridge = new L2Bridge(lZEndPoint);

        //set up the trustedRemote addresses
        l1Bridge.setTrustedRemote(
            layerzeroAVAXChainID,
            abi.encodePacked(address(l2Bridge), address(l1Bridge))
        ); //allow calls to l2bridge
        l2Bridge.setTrustedRemote(
            layerzeroMainnetChainID,
            abi.encodePacked(address(l1Bridge), address(l2Bridge))
        ); //allow calls to l1 bridge

        vm.stopPrank();
    }
}

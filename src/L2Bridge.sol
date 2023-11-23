// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
pragma abicoder v2;

import "./LayerZero/NonblockingLzApp.sol";
import "./BridgeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Bridge is NonblockingLzApp {
    mapping(address => address) L1TokenVersionOnL2;
    mapping (address => address) L2TokenVersionOnL1;
    mapping (address => bool) isBridgeToken;

    using SafeERC20 for IERC20;

    error CantDecodeName();
    error CantDecodeSymbol();
    error CantDecodeDecimal();
    error TokenNotAllowed();
    error L1TokenVersionNotRecognized();

    constructor(
        address _endpoint
    ) Ownable(msg.sender) NonblockingLzApp(_endpoint) {}

    function sendToL1Chain(
        address _l2tokenAddress,
        uint amount,
        uint16 _dstChainId
    ) public payable {
        //check if token is allowed 
        if (isBridgeToken[_l2tokenAddress] == false) revert TokenNotAllowed();

        //Burn l2 token
        BridgeERC20(_l2tokenAddress).burn(
            msg.sender,
            amount
        );

       address l1Token = L2TokenVersionOnL1[_l2tokenAddress];

       if (l1Token == address(0)) revert L1TokenVersionNotRecognized();

        uint16 version = 1;
        uint256 gasForDestinationLzReceive = 350000;
        bytes memory adapterParams = abi.encodePacked(
            version,
            gasForDestinationLzReceive
        );

        bytes memory payload = abi.encode(
            msg.sender,
            amount,
            l1Token
        );

        _lzSend(
            _dstChainId, // destination chainId
            payload, // abi.encode()'ed bytes
            payable(msg.sender), // refund address
            address(0x0), // future param, unused for this example
            adapterParams, // v1 adapterParams, specify custom destination gas qty
            msg.value
        );
    }

    // FUNCTIONS FOR DECODING INPUTS

    function decodeString(
        bytes memory _input
    ) external pure returns (string memory result) {
        (result) = abi.decode(_input, (string));
    }

    function decodeUint8(
        bytes memory _input
    ) external pure returns (uint8 result) {
        (result) = abi.decode(_input, (uint8));
    }

    // GETTER FUNCTION

    function getERC20Metadata(
        address _tokenAddress
    )
        public
        returns (
            string memory decodedName,
            string memory decodedSymbol,
            uint8 decodedDecimals
        )
    {
        (bool nameCallResult, bytes memory tokenName) = _tokenAddress
            .staticcall(abi.encodeWithSignature("name()"));
        (bool symbolCallResult, bytes memory tokenSymbol) = _tokenAddress
            .staticcall(abi.encodeWithSignature("symbol()"));
        (bool decimalCallResult, bytes memory tokenDecimals) = _tokenAddress
            .staticcall(abi.encodeWithSignature("decimals()"));

        try this.decodeString(tokenName) returns (string memory nameString) {
            decodedName = nameString;
        } catch {
            revert CantDecodeName();
        }

        try this.decodeString(tokenSymbol) returns (
            string memory symbolString
        ) {
            decodedSymbol = symbolString;
        } catch {
            revert CantDecodeSymbol();
        }

        try this.decodeUint8(tokenDecimals) returns (uint8 decimals) {
            decodedDecimals = decimals;
        } catch {
            revert CantDecodeDecimal();
        }
    }

    // INTERNAL FUNCTIONS
    function _receiveFromSourceChain(bytes memory _payload) internal {
        //upon message receipt, decode payload and mint token to user on the l2 chain.
        //deploy a new token contract if nexessary.

        (
            address recipient,
            uint tokenAmount,
            address l1TokenAddress,
            string memory tokenName,
            string memory tokenSymbol,
            uint8  tokenDecimals
        ) = abi.decode(
                _payload,
                (address, uint, address, string, string, uint8)
            );

        address l2Token = L1TokenVersionOnL2[l1TokenAddress];

        if (l2Token == address(0)) {
            //DEPLOY
            BridgeERC20 _l2Token = new BridgeERC20(
                owner(),
                tokenName,
                tokenSymbol,
                tokenDecimals
            );
            //register token 
            isBridgeToken[address(_l2Token)] = true; 

            //save new l2 token address
            L1TokenVersionOnL2[l1TokenAddress] = address(_l2Token);
            //save l1 token to l2 token mapping 
            L2TokenVersionOnL1[address(_l2Token)] = l1TokenAddress;
        }

        //after deploy, mint bridged amount to the user
        BridgeERC20(l2Token).mint(recipient, tokenAmount);
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal virtual override {
        _receiveFromSourceChain(_payload);
    }
}

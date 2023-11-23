// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
pragma abicoder v2;

import "./LayerZero/NonblockingLzApp.sol";
import "./BridgeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Bridge is NonblockingLzApp {
    mapping(address => address) L1TokenVersionOnL2;

    using SafeERC20 for IERC20;

    error CantDecodeName();
    error CantDecodeSymbol();
    error CantDecodeDecimal();

    constructor(
        address _endpoint
    ) Ownable(msg.sender) NonblockingLzApp(_endpoint) {}

    function sendToL2Chain(
        address _tokenAddress,
        uint amount,
        uint16 _dstChainId
    ) public payable {
        //collect token.
        uint balBefore = IERC20(_tokenAddress).balanceOf(address(this));
        IERC20(_tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        uint balAfter = IERC20(_tokenAddress).balanceOf(address(this));

        // do this to circumvert funny erc20 token transfer quirks
        amount = balAfter - balBefore;

        uint16 version = 1;
        uint256 gasForDestinationLzReceive = 350000;
        bytes memory adapterParams = abi.encodePacked(
            version,
            gasForDestinationLzReceive
        );

        (
            string memory tokenName,
            string memory tokenSymbol,
            uint8 tokenDecimals
        ) = getERC20Metadata();

        bytes memory payload = abi.encode(
            msg.sender,
            amount,
            _tokenAddress,
            tokenName,
            tokenSymbol,
            tokenDecimals
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

        try this.decodeUint8(tokenDecimals) returns (uint8 memory decimals) {
            decodedDecimals = decimals;
        } catch {
            revert CantDecodeDecimal();
        }
    }

    // INTERNAL FUNCTIONS
    function _receiveFromL2Chain(bytes memory _payload) internal {
        //upon message receipt, decode payload and SEND token to user on the L1 chain.
        (
            address recipient,
            uint tokenAmount,
            address tokenAddress,
        ) = abi.decode(
                _payload,
                (address, uint, address)
            );

        //transfer
        IERC20(tokenAddress).safeTransfer(recipient, tokenAmount);
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

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
pragma abicoder v2;

import "./LayerZero/NonblockingLzApp.sol";
import "./BridgeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title L1 Bridge that allows for cross chain transfer of value
/// @author github:@adeolu98
/// @notice L1 Bridge contract that holds l1 assets and
/// communicates with l2 couterpart to mint l2 token backed by l1 asset to user
contract L1Bridge is NonblockingLzApp, ReentrancyGuard {
    mapping(address => address) L1TokenVersionOnL2;

    using SafeERC20 for IERC20;

    event BridgeToL2(uint16 dstChainId, address sender, bytes payload);
    event ReceivedFromL2(bytes payload, address token, uint amountBridged);

    error CantDecodeName();
    error CantDecodeSymbol();
    error CantDecodeDecimal();

    constructor(
        address _endpoint
    ) Ownable(msg.sender) NonblockingLzApp(_endpoint) {}

    /// @notice caller sends assets to l2 chain
    /// @dev collects token from user, sends message to l2 bridge via layerzero infra
    /// @param _tokenAddress address of token to bridge.
    /// @param amount amount of tokens to send.
    /// @param _dstChainId destination chain id. layerzero ids are different from evm ids. check for your specific l2 id here ->  https://layerzero.gitbook.io/docs/technical-reference/mainnet/supported-chain-ids    uint16 layerzeroAVAXChainID = 106; // from the docs -> https://layerzero.gitbook.io/docs/technical-reference/mainnet/supported-chain-ids
    /// @return payload this is the data transferred across chains to the l2 bridge.
    function sendToL2Chain(
        address _tokenAddress,
        uint amount,
        uint16 _dstChainId
    ) public payable returns (bytes memory payload) {
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
        ) = getERC20Metadata(_tokenAddress);

        payload = abi.encode(
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

        emit BridgeToL2(_dstChainId, msg.sender, payload);
    }

    // FUNCTIONS FOR DECODING INPUTS

    /// @notice converts bytes to string
    /// @param _input paramater to be converted to string
    /// @return result is the string value of the bytes input
    function decodeString(
        bytes memory _input
    ) external pure returns (string memory result) {
        (result) = abi.decode(_input, (string));
    }

    /// @notice converts bytes to uint8
    /// @param _input paramater to be converted to uint8
    /// @return result is the  uint8 value of the bytes input
    function decodeUint8(
        bytes memory _input
    ) external pure returns (uint8 result) {
        (result) = abi.decode(_input, (uint8));
    }

    // GETTER FUNCTION

    /// @dev used to fetch the name, symbol and decimal of a token contract (metadata).
    /// staticcall is used to ensure reverts on any state change. call will revert if bytes fails to be converted to string or uint8
    /// @param _tokenAddress address of token to fetch its metadata
    /// @return decodedName the string representation of the name which was in bytes
    /// @return decodedSymbol the string representation of the symbol which was in bytes
    /// @return decodedDecimals the uint8 representation of the  decimals which was in bytes
    function getERC20Metadata(
        address _tokenAddress
    )
        public
        view
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
        require(
            nameCallResult && symbolCallResult && decimalCallResult,
            "failed to get token metadata"
        );

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

    /// @dev decodes the payload from the cross chain message and sends token to the user.
    /// @param _payload the payload variable from the layerzero cross chain msg
    ///make  fcn reentrant, trust no one, not even LZ.
    function _receiveFromL2Chain(bytes memory _payload) internal nonReentrant {
        //upon receiving message, decode payload and SEND token to user on the L1 chain.
        (address recipient, uint tokenAmount, address tokenAddress) = abi
            .decode(_payload, (address, uint, address));

        //transfer
        IERC20(tokenAddress).safeTransfer(recipient, tokenAmount);

        emit ReceivedFromL2(_payload, tokenAddress, tokenAmount);
    }

    /// @dev lzApp functions that are called in the execution path of lzReceive()
    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal virtual override {
        _receiveFromL2Chain(_payload);
    }
}

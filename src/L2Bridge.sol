// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
pragma abicoder v2;

import "./LayerZero/NonblockingLzApp.sol";
import "./BridgeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title L2 Bridge that allows for cross chain transfer of value
/// @author github:@adeolu98
/// @notice L2 Bridge contract that burns the l2 assets backed by l1 bridge value and
/// communicates with l1 couterpart via layerzero to send l1 token asset to user
contract L2Bridge is NonblockingLzApp, ReentrancyGuard {
    mapping(address => address) public L1TokenVersionOnL2;
    mapping(address => address) public L2TokenVersionOnL1;
    mapping(address => bool) isBridgeToken;

    event BridgeToL1(uint16 dstChainId, address sender, bytes payload);
    event ReceivedFromL1(
        bytes payload,
        address l1Token,
        address l2Token,
        uint amountBridged
    );

    error CantDecodeName();
    error CantDecodeSymbol();
    error CantDecodeDecimal();
    error TokenNotAllowed();
    error L1TokenVersionNotRecognized();

    using SafeERC20 for IERC20;

    constructor(
        address _endpoint
    ) Ownable(msg.sender) NonblockingLzApp(_endpoint) {}

    /// @notice caller sends assets to l1 chain
    /// @dev burns token from user, sends message to l1 bridge via layerzero infra, l1 bridge sends asset to user
    /// @param _l2tokenAddress address of token to bridge.
    /// @param amount amount of tokens to  bridge.
    /// @param _dstChainId destination chain id. layerzero ids are different from evm ids. check for your specific l2 id here ->  https://layerzero.gitbook.io/docs/technical-reference/mainnet/supported-chain-ids    uint16 layerzeroAVAXChainID = 106; // from the docs -> https://layerzero.gitbook.io/docs/technical-reference/mainnet/supported-chain-ids
    /// @return payload this is the data transferred across chains to the l1 bridge.
    function sendToL1Chain(
        address _l2tokenAddress,
        uint amount,
        uint16 _dstChainId
    ) public payable returns (bytes memory payload) {
        //check if token is allowed
        if (isBridgeToken[_l2tokenAddress] == false) revert TokenNotAllowed();

        //Burn l2 token
        BridgeERC20(_l2tokenAddress).burn(msg.sender, amount);

        address l1Token = L2TokenVersionOnL1[_l2tokenAddress];

        if (l1Token == address(0)) revert L1TokenVersionNotRecognized();

        uint16 version = 1;
        uint256 gasForDestinationLzReceive = 350000;
        bytes memory adapterParams = abi.encodePacked(
            version,
            gasForDestinationLzReceive
        );

        payload = abi.encode(msg.sender, amount, l1Token);

        _lzSend(
            _dstChainId, // destination chainId
            payload, // abi.encode()'ed bytes
            payable(msg.sender), // refund address
            address(0x0), // future param, unused for this example
            adapterParams, // v1 adapterParams, specify custom destination gas qty
            msg.value
        );

        emit BridgeToL1(_dstChainId, msg.sender, payload);
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

    /// @dev decodes the payload from the cross chain message and sends token to the user.
    /// @param _payload the payload variable from the layerzero cross chain msg
    ///make  fcn reentrant, trust no one, not even LZ.
    function _receiveFromL1Chain(bytes memory _payload) internal nonReentrant {
        //upon message receipt, decode payload and mint token to user on the l2 chain.
        //deploy a new token contract if necessary.

        (
            address recipient,
            uint tokenAmount,
            address l1TokenAddress,
            string memory tokenName,
            string memory tokenSymbol,
            uint8 tokenDecimals
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

            l2Token = address(_l2Token); //save new token address

            //register token
            isBridgeToken[address(_l2Token)] = true;

            //save new l2 token address
            L1TokenVersionOnL2[l1TokenAddress] = address(_l2Token);
            //save l1 token to l2 token mapping
            L2TokenVersionOnL1[address(_l2Token)] = l1TokenAddress;
        }

        //after deploy, mint bridged amount to the user
        BridgeERC20(l2Token).mint(recipient, tokenAmount);

        emit ReceivedFromL1(_payload, l1TokenAddress, l2Token, tokenAmount);
    }

    /// @dev lzApp functions that are called in the execution path of lzReceive()
    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal virtual override {
        _receiveFromL1Chain(_payload);
    }
}

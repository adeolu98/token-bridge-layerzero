// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title the l2bridge ERC20 token that is backed by tokens held in L1Bridge
/// @author github:@adeolu98
/// @notice token that represents the bridged l1 token on l2
contract BridgeERC20Paused is ERC20, ERC20Burnable, Ownable {
    address public bridge;
    uint8 tokenDecimals;
    bool public paused;

    constructor(
        address _initialOwner,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol) Ownable(_initialOwner) {
        bridge = msg.sender;
        tokenDecimals = _decimals;
    }

    modifier onlyOwnerOrBridge() {
        require(
            msg.sender == bridge || msg.sender == owner(),
            "BridgeERC20: not owner or bridge"
        );
        _;
    }

    modifier isPaused() {
        if (paused == true) revert("token paused");
        _;
    }

    function transfer(address to, uint256 value) public isPaused override returns (bool) {
        return super.transfer(to, value);
    }

    function changePausedState(bool _paused) public onlyOwnerOrBridge {
        paused = _paused;
    }

    /// @return token decimal amount
    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }

    /// @dev callable by bridge and owner only, mints token
    /// @param to address to mint token to
    /// @param amount amount of tokens to mint
    function mint(address to, uint256 amount) public onlyOwnerOrBridge {
        _mint(to, amount);
    }

    /// @dev callable by bridge and owner only, burns token
    /// @param from address to burn token from
    /// @param amount amount of tokens to burn
    function burn(address from, uint256 amount) public onlyOwnerOrBridge {
        _burn(from, amount);
    }
}

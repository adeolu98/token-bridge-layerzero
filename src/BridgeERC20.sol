// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
//import "../lib/StringBytes.sol";

contract BridgeERC20 is ERC20, ERC20Burnable, Ownable {

    address public bridge;
    uint8 tokenDecimals;

    constructor(
        address _initialOwner,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol) Ownable(_initialOwner) {
        bridge = msg.sender;
        tokenDecimals = _decimals;
    }

    modifier onlyOwnerOrBridge {
        require( msg.sender == bridge || msg.sender == owner(), 'BridgeERC20: not owner or bridge');
        _;
    }

    function decimals() public view override returns(uint8) {
   return tokenDecimals;
    }

    /// @dev callable by bridge and owner only
    function mint(address to, uint256 amount) public onlyOwnerOrBridge {
        _mint(to, amount);
    }

    /// @dev callable by bridge and owner only
    function burn(address from, uint256 amount) public onlyOwnerOrBridge {
        _burn(from, amount);
    }
}

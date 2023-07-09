// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {NoDelegateCall} from "@uniswap/v4-core/contracts/NoDelegateCall.sol";

/// @notice Stripped down ERC20 receipt token for Uniswap V4
contract UNI20 is NoDelegateCall {
    bytes32 public immutable name;

    bytes32 public immutable symbol;

    uint8 public immutable decimals;

    address public immutable poolManager;

    address public immutable hook;

    mapping(address => uint256) public balanceOf;

    event Transfer(address indexed from, address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        bytes32 _name,
        bytes32 _symbol,
        uint8 _decimals,
        address _poolManager
    ) NoDelegateCall() {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        poolManager = _poolManager;
        hook = msg.sender;
    }

    function transfer(
        address to,
        uint256 amount
    ) public noDelegateCall returns (bool) {
        if (to == poolManager || to == hook) {
            balanceOf[msg.sender] -= amount;
            unchecked {
                balanceOf[to] += amount;
            }
        }

        if (msg.sender == poolManager) {
            balanceOf[msg.sender] -= amount;
            // No need to increment user tokens since they receive underlying
        }
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public noDelegateCall returns (bool) {
        require(
            msg.sender == poolManager || msg.sender == hook,
            "UNI20: Only pool manager can transfer from"
        );

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        return true;
    }

    function _mint(address to, uint256 amount) external noDelegateCall {
        require(msg.sender == hook, "UNI20: Only hook can mint");
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(address(0), to, amount);
    }

    function _burn(address to) external noDelegateCall {
        require(msg.sender == hook, "UNI20: Only hook can burn");

        balanceOf[to] = 0;
    }
}

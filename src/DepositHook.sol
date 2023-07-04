// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {BaseHook} from "v4-periphery/BaseHook.sol";
import {Pool} from "@uniswap/v4-core/contracts/libraries/Pool.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolId} from "@uniswap/v4-core/contracts/libraries/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/contracts/libraries/CurrencyLibrary.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {UniV4UserHook} from "./UniV4UserHook.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import "forge-std/Test.sol";

contract DepositHook is UniV4UserHook, Test {
    using FixedPointMathLib for uint256;
    using PoolId for IPoolManager.PoolKey;
    using CurrencyLibrary for Currency;

    struct VaultParams {
        int28 tickLower;
        int28 tickUpper;
        ERC4626 token0;
        ERC4626 token1;
        address owner;
    }
    // -- state -- //
    address private owner;
    mapping(PoolId => VaultParams) public pairToVault;

    constructor(IPoolManager _poolManager) UniV4UserHook(_poolManager) {}

    // Simple hook that deposits tokens into a designated 4626 vault
    function getHooksCalls() public pure override returns (Hooks.Calls memory) {
        return
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: true,
                afterModifyPosition: true,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: true
            });
    }

    function initializePool(
        PoolId memory key,
        uint160 sqrtPriceX96,
        VaultParams calldata vault
    ) external {
        key.hook = address(this);
        poolManager.initializePool(key, sqrtPriceX96);
        pairToVault[key.toId()] = vault;
        poolManager.setHookFees();
        /// todo: add a vault token to represent the position which can be minted and burned on modifyPosition
    }

    function beforeSwap(
        address,
        IPoolManager.PoolKey calldata key,
        IPoolManager.SwapParams calldata params
    ) external override returns (bytes4) {
        VaultParams memory vault = pairToVault[key.toId()];

        if (params.zeroForOne) {
            vault.token1.withdrawAll();
        } else {
            vault.token0.withdrawAll();
        }

        return DepositHook.beforeSwap.selector;
    }

    function afterSwap(
        address,
        IPoolManager.PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta
    ) external override returns (bytes4) {
        VaultParams memory vault = pairToVault[key.toId()];

        return DepositHook.afterSwap.selector;
    }

    // ------------------------------------- //

    // -- Util functions -- //
    function setTickLowerLast(bytes32 poolId, int24 tickLower) private {
        tickLowerLasts[poolId] = tickLower;
    }

    function getTickLower(
        int24 tick,
        int24 tickSpacing
    ) private pure returns (int24) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--; // round towards negative infinity
        return compressed * tickSpacing;
    }

    function getHookSwapFee(
        IPoolManager.PoolKey memory key
    ) external pure returns (uint24) {
        return 3000;
    }
}

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
import {UNI20} from "./Uni20.sol";
import "forge-std/Test.sol";

contract DepositHook is UniV4UserHook, Test {
    using FixedPointMathLib for uint256;
    using PoolId for IPoolManager.PoolKey;
    using CurrencyLibrary for Currency;

    struct VaultParams {
        Uni20 uni0;
        Uni20 uni1;
        ERC4626 token0;
        ERC4626 token1;
        address owner;
        uint256 dust;
        uint256 balToken0;
        uint256 balToken1;
    }
    // -- state -- //
    address private owner;
    mapping(PoolId => VaultParams) public pairToVault;
    mapping(PoolKey => PoolKey) public PoolKeyToUNI20PoolKey;

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
                beforeDonate: true,
                afterDonate: true
            });
    }

    function initializePool(
        PoolKey memory key,
        uint160 sqrtPriceX96,
        VaultParams memory vault
    ) external {
        PoolKey memory origKey = key;
        // Could use create2 for gas efficiency
        UNI20 token0 = new UNI20(
            key.currency0.name + "TKN",
            key.currency0.symbol,
            18,
            address(poolManager)
        );
        UNI20 token1 = new UNI20(
            key.currency1.name + "TKN",
            key.currency1.symbol,
            18,
            address(poolManager)
        );
        vault.uni0 = token0;
        vault.uni1 = token1;
        key.currency0 = token0;
        key.currency1 = token1;
        key.hook = address(this);
        poolManager.initializePool(key, sqrtPriceX96);
        pairToVault[key.toId()] = vault;
        PoolKeyToUNI20PoolKey[origKey] = key;
        /// todo: add a vault token to represent the position which can be minted and burned on modifyPosition
    }

    function beforeSwap(
        address,
        IPoolManager.PoolKey calldata key,
        IPoolManager.SwapParams calldata params
    ) external override returns (bytes4) {
        VaultParams memory vault = pairToVault[key.toId()];

        if (params.zeroForOne) {
            vault.uni0.mint(sender, typeOf(uint256).max);
        } else {
            vault.uni1.mint(sender, typeOf(uint256).max);
        }

        return DepositHook.beforeSwap.selector;
    }

    function afterSwap(
        address swapper,
        IPoolManager.PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta
    ) external override returns (bytes4) {
        VaultParams memory vault = pairToVault[key.toId()];

        if (params.zeroForOne) {
            vault.token0.transferFrom(
                uint256(delta.amount0 * -1),
                address(this)
            );
            vault.token1.withdraw(uint256(delta.amount1), address(this));
            vault.token1.transfer(swapper, uint256(delta.amount1));

            // Uni20 tokens are burned on transfer by poolManager

            vault.uni0.burn(sender);
        } else {
            vault.token1.transferFrom(
                uint256(delta.amount1 * -1),
                address(this)
            );

            vault.token0.withdraw(uint256(delta.amount0), address(this));

            vault.token0.transfer(swapper, uint256(delta.amount0));

            vault.uni1.burn(sender);
        }
        return DepositHook.afterSwap.selector;
    }

    function beforeModifyPosition(
        address sender,
        IPoolManager.PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata params
    ) external returns (bytes4) {
        VaultParams memory vault = pairToVault[key.toId()];
        vault.uni0.mint(sender, typeOf(uint256).max);
        vault.uni1.mint(sender, typeOf(uint256).max);
        return DepositHook.beforeModifyPosition.selector;
    }

    function afterModifyPosition(
        address sender,
        IPoolManager.PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata params,
        BalanceDelta delta
    ) external returns (bytes4) {
        VaultParams memory vault = pairToVault[key.toId()];
        if (delta.amount0 > 0) {
            vault.token0.underlying().transferFrom(
                sender,
                address(this),
                uint256(delta.amount0)
            );
            vault.token0.deposit(uint256(delta.amount0), address(this));
        } else if (delta.amount0 < 0) {
            uint256 amount0 = uint256(delta.amount0 * -1);
            vault.token0.withdraw(amount0, address(this));

            vault.token0.underlying().transfer(sender, amount0);
        }
        if (delta.amount1 > 0) {
            vault.token1.underlying().transferFrom(
                sender,
                address(this),
                uint256(delta.amount1)
            );
            vault.token1.deposit(uint256(delta.amount1), address(this));
        } else if (delta.amount1 < 0) {
            uint256 amount1 = uint256(delta.amount1 * -1);
            vault.token1.withdraw(amount1, address(this));

            vault.token1.underlying().transfer(sender, amount1);
        }

        vault.uni0.burn(sender);
        vault.uni1.burn(sender);
        return DepositHook.afterModifyPosition.selector;
    }

    function beforeDonate(
        address,
        IPoolManager.PoolKey calldata key,
        uint256 amount0,
        uint256 amount1
    ) external override returns (bytes4) {
        VaultParams memory vault = pairToVault[key.toId()];
        if (amount0 > 0) {
            vault.token0.underlying().transferFrom(
                sender,
                address(this),
                amount0
            );
            vault.token0.deposit(amount0, address(this));
        }
        if (amount1 > 0) {
            vault.token1.underlying().transferFrom(
                sender,
                address(this),
                amount1
            );
            vault.token1.deposit(amount1, address(this));
        }
        vault.uni0.mint(sender, typeOf(uint256).max);
        vault.uni1.mint(sender, typeOf(uint256).max);
        return DepositHook.beforeDonate.selector;
    }

    function afterDonate(
        address sender,
        IPoolManager.PoolKey calldata key,
        uint256 amount0,
        uint256 amount1
    ) external returns (bytes4) {
        VaultParams memory vault = pairToVault[key.toId()];
        vault.uni0.burn(sender);
        vault.uni1.burn(sender);
        return DepositHook.afterDonate.selector;
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
}

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import './PeripheryImmutableState.sol';
import '../interfaces/IPoolInitializer.sol';

/// @title Creates and initializes V3 Pools
abstract contract PoolInitializer is IPoolInitializer, PeripheryImmutableState {
    /// @inheritdoc IPoolInitializer
    // 用户创建交易对（token0+token1+fee）时，调用该函数
    function createAndInitializePoolIfNecessary(
        // token0地址
        address token0,
        // token1地址
        address token1,
        // 手续费等级
        uint24 fee,
        // 初始化价格的平方根
        uint160 sqrtPriceX96
    ) external payable override returns (address pool) {
        require(token0 < token1);
        // 从factory中获取该交易对（token0+token1+fee）的pool地址
        pool = IUniswapV3Factory(factory).getPool(token0, token1, fee);

        if (pool == address(0)) {
            // 如果该交易对还没有创建，调用factory.createPool()去创建pool
            pool = IUniswapV3Factory(factory).createPool(token0, token1, fee);
            //
            IUniswapV3Pool(pool).initialize(sqrtPriceX96);
        } else {
            // 如果该pool已经被创建，看该pool的slot0中的当前价格的平方根的值
            (uint160 sqrtPriceX96Existing, , , , , , ) = IUniswapV3Pool(pool).slot0();
            if (sqrtPriceX96Existing == 0) {
                // 如果该pool的当前价格平方根为0，表示还没有初始化价格过，直接进行价格初始化
                IUniswapV3Pool(pool).initialize(sqrtPriceX96);
            }
        }
    }
}

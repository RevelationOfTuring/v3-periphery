// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';

import '../libraries/PoolAddress.sol';
import '../libraries/CallbackValidation.sol';
import '../libraries/LiquidityAmounts.sol';

import './PeripheryPayments.sol';
import './PeripheryImmutableState.sol';

/// @title Liquidity management functions
/// @notice Internal functions for safely managing liquidity in Uniswap V3
abstract contract LiquidityManagement is IUniswapV3MintCallback, PeripheryImmutableState, PeripheryPayments {
    struct MintCallbackData {
        PoolAddress.PoolKey poolKey;
        address payer;
    }

    /// @inheritdoc IUniswapV3MintCallback
    // pool在添加流动性时需要回调本合约的回调函数
    function uniswapV3MintCallback(
        // 用于注入pool的token0的数量
        uint256 amount0Owed,
        // 用于注入pool的token1的数量
        uint256 amount1Owed,
        // 执行回调时的参数
        bytes calldata data
    ) external override {
        // 将bytes的calldata转换成结构体MintCallbackData
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));
        // 做回调校验——要求回调的msg.sender必须是对应MintCallbackData.poolKey对应的pool
        CallbackValidation.verifyCallback(factory, decoded.poolKey);

        // 执行回调：
        // 如果amount0Owed>0，将这些数量的decoded.poolKey.token0从decoded.payer转给msg.sender（即对应pool）
        if (amount0Owed > 0) pay(decoded.poolKey.token0, decoded.payer, msg.sender, amount0Owed);
        // 如果amount1Owed>0，将这些数量的decoded.poolKey.token1从decoded.payer转给msg.sender（即对应pool）
        if (amount1Owed > 0) pay(decoded.poolKey.token1, decoded.payer, msg.sender, amount1Owed);
    }

    struct AddLiquidityParams {
        // token0地址
        address token0;
        // token1地址
        address token1;
        // 手续费等级
        uint24 fee;
        // LP token的接收者
        address recipient;
        // 添加流动性的价格区间的下限的tick index（以token0计价）。前端需要通过用户输入的价格下限算出
        int24 tickLower;
        // 添加流动性的价格区间的上限的tick index（以token0计价）。前端需要通过用户输入的价格上限算出
        int24 tickUpper;
        // LP期待的注入token0的数量
        uint256 amount0Desired;
        // LP期待的注入token1的数量
        uint256 amount1Desired;
        // LP能接受的注入token0的最小数量
        uint256 amount0Min;
        // LP能接受的注入token1的最小数量
        uint256 amount1Min;
    }

    /// @notice Add liquidity to an initialized pool
    // 用户向一个pool中添加流动性
    function addLiquidity(AddLiquidityParams memory params)
        internal
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1,
            IUniswapV3Pool pool
        )
    {
        // 将AddLiquidityParams中的token0和token1地址排序，得到标准的PoolKey
        PoolAddress.PoolKey memory poolKey =
            PoolAddress.PoolKey({token0: params.token0, token1: params.token1, fee: params.fee});

        // 利用PoolKey计算得到pool的地址
        pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));

        // compute the liquidity amount
        // 计算本次添加的流动性
        {
            // 获取该pool的当前价格的平方根
            (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
            // 由提供流动性价格区间的下限tick求出对应的价格的平方根
            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(params.tickLower);
            // 由提供流动性价格区间的上限tick求出对应的价格的平方根
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(params.tickUpper);
            // 合约中通过价格区间、当前价格以及用户想要注入的token0和token1的数量计算出本次可以添加出来的最大流动性
            liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                params.amount0Desired,
                params.amount1Desired
            );
        }

        // 调用对应pool，注入流动性（传入recipient/添加流动性的上下价格区间对应的tick index/要添加的流动性大小）
        // 注：v3是使用回调函数来完成最后流动性token的注入
        //    即pool会回调NonfungiblePositionManager.uniswapV3MintCallback()来完成token的注入）
        // amount0为真正注入到pool中的token0的数量
        // amount1为真正注入到pool中的token1的数量
        (amount0, amount1) = pool.mint(
            params.recipient,
            params.tickLower,
            params.tickUpper,
            liquidity,
            // pool合约中的回调函数MintCallbackData所需要的参数
            abi.encode(MintCallbackData({poolKey: poolKey, payer: msg.sender}))
        );

        // 最后校验: 真正注入pool的token{0,1}的数量需要 >= LP能接受的注入token{0,1}的最小数量
        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, 'Price slippage check');
    }
}

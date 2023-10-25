// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import '../interfaces/IPeripheryImmutableState.sol';

/// @title Immutable state
/// @notice Immutable state used by periphery contracts
abstract contract PeripheryImmutableState is IPeripheryImmutableState {
    /// @inheritdoc IPeripheryImmutableState
    // factory合约地址
    address public immutable override factory;
    /// @inheritdoc IPeripheryImmutableState
    // weth的地址
    address public immutable override WETH9;

    constructor(address _factory, address _WETH9) {
        // 初始化将factory地址和weth地址写入immutable变量
        factory = _factory;
        WETH9 = _WETH9;
    }
}

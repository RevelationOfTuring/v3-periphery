// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import '../interfaces/IPeripheryPayments.sol';
import '../interfaces/external/IWETH9.sol';

import '../libraries/TransferHelper.sol';

import './PeripheryImmutableState.sol';

abstract contract PeripheryPayments is IPeripheryPayments, PeripheryImmutableState {
    // 本合约只接受weth转入的eth
    receive() external payable {
        require(msg.sender == WETH9, 'Not WETH9');
    }

    /// @inheritdoc IPeripheryPayments
    function unwrapWETH9(uint256 amountMinimum, address recipient) public payable override {
        // 本合约的weth余额
        uint256 balanceWETH9 = IWETH9(WETH9).balanceOf(address(this));
        // 要求weth余额需要>=amountMinimum
        require(balanceWETH9 >= amountMinimum, 'Insufficient WETH9');

        if (balanceWETH9 > 0) {
            // 如果本合约的weth余额>0，将其换成eth
            IWETH9(WETH9).withdraw(balanceWETH9);
            // 并将等额的eth转给recipient
            TransferHelper.safeTransferETH(recipient, balanceWETH9);
        }
    }

    /// @inheritdoc IPeripheryPayments
    // 从本合约转出任何ERC20（任何人都可以转，只要本合约中有ERC20余额）
    function sweepToken(
        // 转出ERC20地址
        address token,
        // 要转出的最小数量
        uint256 amountMinimum,
        // 接受者
        address recipient
    ) public payable override {
        // 获取本合约名下该ERC20的余额
        uint256 balanceToken = IERC20(token).balanceOf(address(this));
        // 要求余额需要>=amountMinimum
        require(balanceToken >= amountMinimum, 'Insufficient token');

        if (balanceToken > 0) {
            // 如果余额大于0，就将本合约名下所有的该ERC20代币都转给recipient
            TransferHelper.safeTransfer(token, recipient, balanceToken);
        }
    }

    /// @inheritdoc IPeripheryPayments
    // 从本合约转出eth（任何人都可以转，只要本合约中有eth余额）
    function refundETH() external payable override {
        if (address(this).balance > 0) TransferHelper.safeTransferETH(msg.sender, address(this).balance);
    }

    /// @param token The token to pay
    /// @param payer The entity that must pay
    /// @param recipient The entity that will receive payment
    /// @param value The amount to pay
    // uniswap封装好的转移token的函数
    function pay(
        // 转移token的地址
        address token,
        // from地址
        address payer,
        // to地址
        address recipient,
        // 转移数量
        uint256 value
    ) internal {
        if (token == WETH9 && address(this).balance >= value) {
            // pay with WETH9
            // 如果要转移WETH且本合约的eth余额>=value，那么会自动将eth转为weth
            // 将value数量的eth转为weth（to本合约）
            IWETH9(WETH9).deposit{value: value}(); // wrap only what is needed to pay
            // 将value数量的weth转给recipient(from 本合约，to recipient)
            IWETH9(WETH9).transfer(recipient, value);
        } else if (payer == address(this)) {
            // 如果不是转移weth且本合约eth余额>=value，同时payer是本合约(即将token从本合约转出去)
            // pay with tokens already in the contract (for the exact input multihop case)
            // 利用TransferHelper直接转账
            TransferHelper.safeTransfer(token, recipient, value);
        } else {
            // pull payment
            // 不满足以上条件，说明是授权转帐——利用TransferHelper的safeTransferFrom进行授权转账
            TransferHelper.safeTransferFrom(token, payer, recipient, value);
        }
    }
}
